require 'yaml'
require 'json'
require 'logger'
require 'bunny'

require 'ghtorrent/api_client'
require 'ghtorrent/settings'
require 'ghtorrent/logging'
require 'ghtorrent/command'

class GetOrgRepos < GHTorrent::Command

  include GHTorrent::Settings
  include GHTorrent::Logging
  include GHTorrent::Persister
  include GHTorrent::APIClient
  include GHTorrent::Logging

  def prepare_options(options)
    options.banner <<-BANNER
Manages GHTorrent's relationship with GitHub by discovering orgs for a user,
discovering repos for orgs and managing webhooks for orgs. This is primarily useful
in webhook-based scenarios.

The orgs parameter is the file path to a flat file listing orgs to consider or update.
The repos parameter is the file path to a flat file to be updated with the list of repos
in the given/discovered orgs

#{command_name} [options]
    BANNER
    options.opt :orgs, 'Path to org list file to be read/written',
                :short => 'o', :type => String
    options.opt :repos, 'Path to repo list file to be written',
                :short => 'r', :type => String
    options.opt :force, 'Whether or not to force updating the orgs list',
                :short => 'f', :default => false
    options.opt :token_read, 'The read token to be used to complete this operation',
                :short => 't', :default => false, :type => String
    options.opt :token_webhook, 'The webhook token to be used to create webhooks for orgs',
                :short => 'w', :default => false, :type => String
    options.opt :secret_webhook, 'The webhook secret to be used to create webhooks for orgs',
                :short => 's', :default => false, :type => String
  end

  def load_orgs(path)
    if @options[:force]
      orgs = paged_api_request "https://api.github.com/user/orgs"
      if orgs.nil?
        warn "No Organizations found"
        return []
      end

      org_list = orgs.collect |x| x['login']
      write_list(nil, org_list, path)
      return org_list
    end

    # read the orgs file and break it into trimmed lines
    begin
      return File.readlines(path).collect |entry| entry strip
    rescue IOError => e
      warn "error reading #{path}"
    end
  end

  def update_repos_list(orgs, path)
    if orgs.nil?
      warn "No Organizations provided"
      return
    end

    orgs.each do |org|
      repos = paged_api_request "https://api.github.com/orgs/#{org}/repos"
      if repos.nil?
        info "No repositories for Organization #{org}"
      else
        list = repos.collect |x| x['name']
        write_list(org, list, path)
      end
    end
  end

  def write_list(prefix, list, path)
    prefix = prefix.nil? ? '' : prefix + ' '
    begin
      file = File.open(path, 'a')
      list.each do |entry|
        file.puts prefix + entry
      end
    rescue IOError => e
      warn "error writing list to #{path}"
    ensure
      file.close unless file.nil?
    end
  end

  def check_web_hook(org, hook_url, secret)
    return if hook_url.nil?

    # retrieve the org's hook
    hooks = paged_api_request "https://api.github.com/orgs/#{org}/hooks"
    if hooks.nil?
      info "Error getting hooks for Organization #{org}"
    end

    # return nil if url is already present in org hooks
    hook = hooks.select do |hook|
      hook.config.url.downcase === hook_url.downcase
    end
    unless hook.empty?
    #TODO: implement me
    #POST https://api.github.com/orgs/#{org}/hooks
    #config = {
    #  url: hookUrl,
    #  content_type: 'json',
    #  secret: secret
    #};
    #  return github.orgs.createHook({ org: org, name: 'web', config: config, events: '*', active: true });
    end
  end

  def go
    orgs = load_orgs(@options[:orgs])
    update_repos_list(orgs, @options[:repos])
    unless @options[:url_webhook].nil?
      orgs.each do |org|
        check_web_hook(org, @options[:url_webhook], @options[:secret_webhook])
      end
    end
  end
end
