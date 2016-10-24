require 'yaml'
require 'json'
require 'logger'
require 'bunny'

require 'ghtorrent/api_client'
require 'ghtorrent/settings'
require 'ghtorrent/logging'
require 'ghtorrent/command'

class ManageOrgs < GHTorrent::Command

  include GHTorrent::Settings
  include GHTorrent::APIClient
  include GHTorrent::Logging

  def rabbit
    @rabbit ||= connect_rabbit
    @rabbit
  end

  def prepare_options(options)
    options.banner <<-BANNER
Manages GHTorrent's relationship with GitHub by discovering orgs for a user,
discovering repos for orgs and managing webhooks for orgs. This is primarily useful
in webhook-based scenarios.

The orgs parameter is the file path to a flat file listing orgs to consider or update.
The repos parameter is the file path to a flat file to be updated with the list of repos
in the given/discovered orgs.

#{command_name} [options]
    BANNER
    options.opt :orgs, 'Path to org list file to be read/written',
                :short => 'o', :type => String, :default => nil
    options.opt :force, 'Whether or not to force updating the orgs list',
                :short => 'f', :default => false
    options.opt :queue, 'Whether or not to queue newly discovered repos for full retrieval',
                :short => 'q', :default => false
    options.opt :webhook, 'URL for org webhooks on discovered orgs. Leave off to skip webhook registration',
                :short => 'w', :type => String, :default => nil
  end

  def go
    orgs = load_orgs(@options[:orgs])
    update_repos_list(orgs, config(:mirror_repos_file), @options[:queue])
    ensure_webhooks(orgs, @options[:webhook]) unless @options[:webhook].nil?
  end

  def load_orgs(path)
    path ||= config(:mirror_orgs_file)
    if @options[:force]
      File.delete(path) if File.exists? path
      orgs = paged_api_request "https://api.github.com/user/orgs"
      if orgs.nil?
        warn "No Organizations found"
        return []
      end

      org_list = orgs.collect{|x| x['login'].downcase}.sort
      write_list(org_list, path)
      return org_list
    end

    # read the orgs file and break it into trimmed lines
    begin
      return File.readlines(path).collect {|entry| entry.strip}.reject { |l| l.nil? }
    rescue IOError => e
      warn "error reading #{path}"
    end
  end

  def update_repos_list(orgs, path, queue)
    if orgs.nil?
      warn "No Organizations provided"
      return
    end

    current = load_file(path)
    File.delete(path) if File.exists? path
    updated = update_repos_file(orgs, path)
    queue_new_repos(current, updated) if queue
  end

  def update_repos_file(orgs, path)
    result = orgs.collect do |org|
      repos = paged_api_request "https://api.github.com/orgs/#{org}/repos"
      if repos.nil?
        info "No repositories for Organization #{org}"
        []
      else
        list = repos.collect{|x| "#{org} #{x['name']}".downcase}.sort
        write_list(list, path)
        list
      end
    end
    return Set.new(result.flatten)
  end

  def load_file(path)
    result = Set.new
    return result unless File.exists?(path)

    IO.foreach(path) do |x|
      x = x.strip
      result.add(x) unless x.empty?
    end
    result
  end

  def queue_new_repos(current, updated)
    discovered = updated.subtract(current)
    return if discovered.empty?

    discovered.each do |repo|
      info "Queuing #{repo} for full retrieval"
      rabbit.publish repo.strip, :persistent => true, :routing_key => GHTorrent::ROUTEKEY_PROJECTS
    end
  end

  def write_list(list, path)
    begin
      file = File.open(path, 'a')
      list.each {|entry| file.puts entry}
    rescue IOError => e
      warn "error writing list to #{path}"
    ensure
      file.close unless file.nil?
    end
  end

  def ensure_webhooks(orgs, hook_url)
    orgs.each {|org| ensure_web_hook(org, hook_url)}
  end

  def ensure_web_hook(org, hook_url)
    return if hook_url.nil?
    http = get_github_http
    request = get_webhook_request(org, 'GET')
    response = http.request(request)
    unless response.code == '200'
      warn "Failed webhook discovery for org: #{org}, Code: #{response.code}"
      return
    end

    hooks = JSON.parse(response.body)
    if hooks.nil? or hooks.empty?
      info "Error getting hooks for Organization #{org}"
    end

    # return nil if url is already present in org hooks
    index = hooks.find_index {|hook| hook['config']['url'].downcase === hook_url.downcase}
    return unless index.nil?

    request = get_webhook_request(org, 'POST')
    body = {
      :name => "web",
      :active => true,
      :events => ["*"],
      :config => {
        :url => hook_url,
        :content_type => "json",
        :secret => config(:github_webhook_secret)
      }
    }
    request.body = body.to_json
    response = http.request(request)
    unless response.code == '201'
      warn "Failed webhook registration for org: #{org}, Code: #{response.code}"
      return
    end
  end

  def get_github_http
    uri = URI.parse("https://api.github.com")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http
  end

  def get_webhook_request(org, method)
    # using direct HTTP calls to avoid requiring octokit just for this scenario
    path = "/orgs/#{org}/hooks"
    request = method == 'GET' ? Net::HTTP::Get.new(path) : Net::HTTP::Post.new(path)
    request.add_field('Content-Type', 'application/json')
    request.delete('Accept-Encoding')
    request['Accept'] = "application/vnd.github.v3+json"
    request['Authorization'] = "token #{config(:github_webhook_token)}"
    request
  end

  def connect_rabbit
    conn = Bunny.new(:host => config(:amqp_host),
                     :port => config(:amqp_port),
                     :username => config(:amqp_username),
                     :password => config(:amqp_password))
    conn.start

    channel  = conn.create_channel
    debug "Connection to #{config(:amqp_host)} succeeded"

    return channel.topic(config(:amqp_exchange), :durable => true, :auto_delete => false)
  end
end
