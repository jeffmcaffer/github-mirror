# ospo-msght
---
ospo-msght is Microsoft's private instance of [GHTorrent](https://github.com/gousiosg/github-mirror). Rather than collecting all public GitHub data, ospo-msght uses webhooks and private GitHub tokens to gather all of __Microsoft's public and private__ GitHub data. The webhook data is automatically added to queues to be used by [ospo-cops](https://github.com/Microsoft/ospo-cops). All data is added to Azure blob storage through daily data dumps. 

##Components

  ospo-msght is made up of three primary components: __GHTorrent__, __webhooks__, and __daily dumps__.
###GHTorrent
  [GHTorrent](https://github.com/gousiosg/github-mirror) is the heart of ospo-msght. According to the README:
  >[GHTorrent is] a library and a collection of scripts used to retrieve data from the Github API and extract metadata in an SQL database, in a modular and scalable manner.
  
  Traditionally, GHTorrent polls GitHub's open event stream and recursively walks the JSON. In contrast, ospo-msght contains a _projects_ file; for each project, GHTorrent's `ght-retrieve-repo` function is called and all data is pulled for that repository (unless it has been pulled within the last ten days). Similar to GHTorrent, all data is stored in a Mongo database as well as a MySQL database.
###Webhooks
GitHub webhooks are used as subscriptions to every Microsoft organization's event stream. If a new org is added to the _org.txt_ file, a webhook will automatically be added when ospo-msght starts up. When an event occurs for any repository in an org with webhooks:
  1. GitHub sends information about the event to a listening server (_ght-webhook_)
  2. The listening server passes the org and repository name to an _api\_client_ script, which continuously pulls events for that repository until it has retrieved all of the new events for that repository
  3. The events are added to Mongo's 'events' collection, then split into their types and added to RabbitMQ queues. These queues push data onto GHTorrent's _ght_data_retrieval_ script and undergo further processing 
    
It's important to note that we don't simply store the data retrieved from the webhook. This is because much of the data differs in formatting - and sometimes even value - from events gathered by the event API.
###Daily Data Dumps
The smallest compononent, daily dumps is composed of a small `ght-periodic-dump` script. This script looks at a _lastrun_ local file and dumps all mongo data between the date stored in that file and the current time. The dump is compressed and sent to Azure blob service. It's important to note that the intermediary files are extremely large, and can __easily__ fill up your storage. If you're doing a large dump, store the intermediary files in a place that can handle their size.

Daily dumps require a connection to Azure, so make sure the `AZURE_STORAGE_ACCOUNT` and `AZURE_STORAGE_ACCESS_KEY` environment variables are set before each dump.

##Logging
Two forms of logging are used:
  1. __Application Insights__
  
  Application Insights is used for logging everything outside of GHTorrent. Webhooks log every event that is sent to the server. ospo-msght logs when it begins gathering data on a repo, finishes gathering data on a repo, or determines if a key does not have access to a repo. Connecting to Application insights requires that the `APPLICATION_INSTRUMENTATIONKEY` environment variable is set.

  2. __Local Logging__
  
  GHTorrent outputs its logs to a local _logfile.txt_ file. This file grows by upwards of 1.5 GB per day, and is thus replaced every time ospo-msght is run. It contains highly detailed information and is very valuable for debugging. Because of this, it would likely be wise to invest time in creating a system to compress and store the daily logfiles on Azure.

##Use ospo-msght

The functions of ospo-msght are a strict superset of those found at [GHTorrent](https://github.com/gousiosg/github-mirror). The main ospo-msght functions can be found in the _msght-functions_ script within _bin_.
  * __startMSGHT \<token_read> \<token_write_hooks>__: Begins the backfilling process for all repositories that haven't been updated within the last ten days. This function automatically updates the projects file. This takes one GitHub token for reading data and another for creating webhooks. Note that these tokens can, obviously, be the same.
  
  * __getRepos \<token_read> \<token_write_hooks>__: Updates the projects file to include all repositories and automatically creates webhooks for all orgs in the orgs file.
  
  * __startWebhooks__: Starts up the webhooks server so that GitHub can send it event data. Note that the events retrieved by webhooks will not be processed unless the `ght-data-retrieval` script is running. Feel free to have multiple instances of this script running.
  
  * __startWebhookListener__: Starts up the process that listens to the logging RabbitMQ queue. The webhooks server can't directly connect to Application Insights (due to conflicting ruby requirements), so it puts events on a logging queue, and this process adds them to Application Insights.
  
Additionally, there is a shell script to run daily dumps called _run_dump.sh_. By using the command `sh run_dump.sh` a dump will be produced and added to Azure. Note that this looks at a local _lastrun_ file which denotes the earliest data to add to the dump. The text in this file should follow the format: `yyy-mm-dd hh:mm`. For example: `2016-08-11 23:59`. If you want to dump all data, simply set the date to be very early.

##Setting up ospo-msght

Setting up ospo-msght is extremely similar to setting up [GHTorrent](https://github.com/gousiosg/github-mirror) with the caveat that you likely do not want to install the `ghtorrent` gem. This gem is outdated and could easily lead to ospo-msght looking as though it's running properly, but in reality it could be running GHTorrent. The two alternatives:
  1. Run the code locally.
  2. Create an ospo-msght gem.

Aside from installing the ruby gem, all other steps should be the same as installing GHTorrent. If you want to devote a server to running ospo-msght, I would advise starting the RabbitMQ server, starting `ght-data-retrieval` (See [GHTorrent](https://github.com/gousiosg/github-mirror)), starting the webhooks server and webhooks logging listener in a script within _/etc/init.d_, and running `startMSGHT` and daily dumps within __Crontab__. Be sure to rename the _lastrun.example_ file to _lastrun_ if you want to do dumps and update the date in that file. 

##TODO

There are many, many ways in which ospo-msght can be improved. Here are some of the changes and additions that I believe would be most fruitful.
  * Create a gem for ospo-msght so as to reduce confusion and ambiguity between GHTorrent and ospo-msght.
  * Alter the _ght-webhook_ script so that it doesn't lock over such a large portion of code.
  * Update logging to store data on individual repository retrievials and safely store all logs.
  * Update _ght-webhook_ logging so that it doesn't use another process for logging (that's just silly).
  * Reduce the _run-msght_ script, perhaps even removing the logic to switch keys if one key does not have access. The problem of determining if a key has access to a repository is challenging in very subtle ways, and the challenge is amplified by the asynchronous nature of the code. This makes it one of the most bug-prone portions of ospo-msght. It is simpler to ensure that all keys used have access to all of the organizations and repositories in question before using them in ospo-msght.
  * Add Application Insights metrics that help indicate if the program is running as expected. Sometimes (perhaps even often times) the hardest part of finding a bug in this program isn't tracking down the code responsible, but realizing that there's a bug at all. Any metrics that could indicate a bug have the potential to be extremely valuable.

##Important Notes
  * Understanding exactly what code is running can be more valuable in this project than others. If the GHTorrent gem is installed on your machine, ospo-msght may be running off of that gem instead of the ospo-msght code. This is exceptionally pernicious. Understanding this possibility can save you countless hours of unnecessary debugging. You're welcome.
  * As counterintuitive as it may seem, more keys may not necessarily be better. Running five `ght-retrieve-repo` processes using one large token is far more efficient than running five `ght-retrieve-repo` processes which each use one regular-sized token because you'll spend __much__ less time waiting for the key to become usable after it has been used up for the hour.
