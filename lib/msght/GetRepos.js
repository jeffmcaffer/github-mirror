/*
 * Script GetRepos.js - script that grabs all github repositories for an Organization and
 * prints them to stdout. This also adds webhooks to all repos that it gathers.
 * The repo and org names can easily be piped into a file using '>' or '>>'.
 * 
 * Input parameters:
 * -org: the name of the organization whose repos you want to grabs
 * -tr: the read token to be used to complete this operation
 * -tw: the webhook token to be used to create webhooks for orgs
 * 
 * example use:
 *   node GetRepos.js -org microsoft -tr 0123456789012345678901234567890123456789 -tw 0123456789012345678901234567890123456789
 */
const exec = require('child_process').exec;
const github = require('octonode');
const cmd_delete_1 = 'curl -X DELETE -H "Authorization: token '
const cmd_delete_2 = '" https://api.github.com/orgs/'
const cmd_delete_3 = '/hooks/';

//Strings for flags
const orgFlag = '-org';
const tokenReadFlag = '-tr';
const tokenHookFlag = '-tw'
const verboseFlag = '-f';

//Booleans to tell if the data was passed in by the user
var setOrg = false;
var setReadToken = false;
var setHookToken = false;

//The data itself that is stored from the commandline arguments
var org, tokenRead, tokenHook;
var verbose = false;

//The command to execute in orer to get the repos
const cmd1 = 'curl -H \'Authorization: token ';
const cmd2 = '\' https://api.github.com/orgs/';
const end_cmd = '/repos?page=';

//The command to execute in order to add a webhook
const cmd_add1 = 'curl -H "Authorization: token '
const cmd_add2 = '" -H "Content-Type: application/json" --data \'{"name":"web", "active":true,"events":["commit_comment", "delete", "deployment_status", "gollum", "issues", "membership", "public", "pull_request_review_comment", "release", "status", "status", "watch", "create", "deployment", "fork", "issue_comment", "member", "page_build", "pull_request", "push", "repository", "team_add"], "config":{"url":"http://104.209.208.162:4567", "secret":"a42b668e52af9aa58c40387c049e8b31470e522e", "content_type":"json"}}\' https://api.github.com/orgs/'
const cmd_add3 = '/hooks';

//The command to execute to list an org's webhooks
const cmd_list1 = 'curl -H "Authorization: token ';
const cmd_list2 = '" https://api.github.com/orgs/';
const cmd_list3 = '/hooks';

//Read through all arguments to find the organization and token
for (var k = 0; k < process.argv.length; k++) {
    switch (process.argv[k]) {
    case orgFlag: //Case: organization name
		org = process.argv[++k];
		setOrg = true;
		break;

    case tokenReadFlag: //Case: token
		tokenRead = process.argv[++k];
		setReadToken = true;
		break;

	case tokenHookFlag:
		tokenHook = process.argv[++k];
		setHookToken = true;
		break;

    case verboseFlag:
		verbose = true;
		break;
    }
}

//If we didn't set the org, inform the user and exit
if (!setOrg) {
    console.log("Must pass org with the -org flag. Exiting");
    process.exit(0);
}
//If we didn't set the token, inform the user and exit
if (!setReadToken || !setHookToken) {
    console.log("Must pass the read and webhook tokens with the -tr and -tw flags, respectively. Exiting");
    process.exit(0);
}

//Check if the webhook exists for this org. If it doesn't, then add it
exec(cmd_list1 + tokenHook + cmd_list2 + org + cmd_list3, function(error, stdin, stdout) {
    if(!GetListWebhooks(error, stdin, stdout)) {
		exec(cmd_add1 + tokenHook + cmd_add2 + org + cmd_add3, GetAddWebhook);
    }
});

//Grab the github client using the read token
var client = github.client(tokenRead);

//Start out with ten repos
GetRepos_TenPages(0);

/*
 * Function GetRepos_TenPages - collects ten pages of repos starting with page startIndex.
 * Automatically calls again if it found data. Stops when it finishes and did not gather
 * any data.
 * 
 * Return: void
 */
function GetRepos_TenPages(startIndex) {
    var repo_count = 0; //Used to indicate when all cmds executed and returned
    var foundData = false; //boolean to tell if we did find name data for repos
    var num_repos = 1;
    //Execute ten times to collect 10 pages of data
    for (var i = 0; i < num_repos; i++) {
		//Execute the command
		exec(cmd1 + tokenRead + cmd2 + org + end_cmd + (startIndex + i), function (error, stdout, stderr) {
			var body = stdout; //Gather the data (in JSON format)
			if(verbose) { console.log(body); }
			
			//Replace all extraneous characters
			body = body.replace('[', '');
			body = body.replace(']', '');
			body = body.replace(',', '');
			var body_lines = body.split('\n'); //split on new line

			//Go over every line to find names
			for (var j in body_lines) {
				//If we find a line that is a repo name
				if (body_lines[j].indexOf('\"name\"') > -1) {
					foundData = true;

					//Split up and replace the name to the point of being printable
					var s = body_lines[j].replace('\"name\": ', '');
					s = s.replace(/\"/g, '');
					s = s.replace(/ /g, '');
					s = s.replace(',', '');
					console.log(org + ' ' + s);
				}
			}

			//If the repo count hits ten, then all commands have finished executing.
			//If we did find data, then do it agian, but on the next ten pages (recursively)
			if (++repo_count == num_repos && foundData) {
				GetRepos_TenPages(startIndex + num_repos);
			}
		});
    }
}

/*
 * Function GetListWebhooks - function that takes in the result of executing the list-repos command. 
 * 
 * Return: true if the webhook already exists, false otherwise.
 */
function GetListWebhooks(error, stdin, stdout) {
    if(error) {
		PrintError(error);
		return;
    }

    try {
		var hooks = JSON.parse(stdin);
		for(var i = 0; i < hooks.length; i++) {
			if(hooks[i]['config']['url'] == 'http://104.209.208.162:4567') {
				return true;
			}
		}
    }
    catch(e) {
		console.log("Hit exception in GetListWebhooks");
		console.log(e);
		return false;
    }
    return false;
}

/*
 * Function GetAddWebhook - function that responds to the execution of the add-webhook command
 *
 * Return: void
 */
function GetAddWebhook(error, stdin, stdout) {
    if(error) {
		PrintError(error);
		return;
    }
}

/*
 * Function PrintError - simple function that prints an exception/error. This is to be used
 *   as a callback for a function that may throw an exception.
 *
 * Return: void
 */
function PrintError(err) {
    if(err) {
		console.log("Hit exception: ");
		console.log(err);
    }
}
