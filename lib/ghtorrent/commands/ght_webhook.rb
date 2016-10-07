#!/usr/bin/env ruby

# (c) 2016 - onwards Georgios Gousios <gousiosg@gmail.com>
#
# MIT licensed, see LICENSE in top level dir
#
# Minimal GitHub webhook for use with GHTorrent.

require 'sinatra/base'
require 'bunny'
require 'mongo'
require 'yaml'
require 'json'
require 'openssl'
require 'json'
require 'thread'

require 'ghtorrent/api_client'
require 'ghtorrent/settings'
require 'ghtorrent/logging'
require 'ghtorrent/command'

class GHTWebHook < GHTorrent::Command
  def prepare_options(options)
    options.banner <<-BANNER
Listens for GitHub webhook events and queues up the corresponding GitHub events for processing.

#{command_name} [options]
    BANNER
  end

  @@semaphore = Mutex.new

  def go
    run WebhookListener.run!
  end
end

class WebhookListener < Sinatra::Base
  include GHTorrent::APIClient

  configure do
    if config(:mongo_username).nil?
      db = Mongo::Client.new(["#{config(:mongo_host)}:#{config(:mongo_port)}"],
                            :database => config(:mongo_db),
                            :ssl => config(:mongo_ssl))
    else
      db = Mongo::Client.new(["#{config(:mongo_host)}:#{config(:mongo_port)}"],
                            :database => config(:mongo_db),
                            :user => config(:mongo_username),
                            :password => config(:mongo_password),
                            :ssl => config(:mongo_ssl))
    end

    db.database.collection_names
    STDERR.puts "Connection to MongoDB: #{config(:mongo_host)} succeeded"

    set :mongo, db
    begin
      conn = Bunny.new(:host => config(:amqp_host),
                      :port => config(:amqp_port),
                      :username => config(:amqp_username),
                      :password => config(:amqp_password),
                      :network_recovery_interval => 7)
      conn.start
    rescue Exception => e
      sleep 2
      retry
    end

    ch = conn.create_channel
    STDERR.puts "Connection to RabbitMQ: #{config['amqp']['host']} succedded"

    @exchange = ch.topic(config(:amqp_exchange), :durable => true, :auto_delete => false)
    set :rabbit, @exchange
  end

  get '/' do
    "ght-web-hook: use POST instead\n"
  end

  post '/' do
    #Verify the signature
    request.body.rewind
    payload_body = request.body.read
    if verify_signature(payload_body)
      puts "verified\r\n"

      # Read and parse event
      begin
        event = JSON.parse(payload_body)
      rescue StandardError => e
        puts e
        halt 400, "Error parsing object #{request.body.read}"
      end

      pull_events(event)
    else
      print "Could not verify\r\n"
      halt 500
    end
  end

  def pull_events(event)
    begin
      puts "Received event for repo: #{event['repository']['full_name']}\r\n"
      repo_parts = event['repository']['full_name'].split('/')
      # GHTorrentWebhook.set_config(config)

      page = 1
      until page > config(:mirror_history_pages_back)
        url = "#{config(:mirror_urlbase)}repos/#{repo_parts[0]}/#{repo_parts[1]}/events?page=#{page}&per_page=100"
        puts "URL is: #{url}"

        begin
          r = paged_api_request(url, 1)
        rescue Exception => e
          puts "#{config(:mirror_urlbase)}: Retrieved all pages. exiting"
          puts e
          return
        end

        if r == nil
          return
        end

        # TODO: Replace this semaphore with:
        #   1. Do HTTP request (above)
        #   2. Call a new synchronized function whose logic is: if the largest
        #      Event ID in HTTP response is > than the largest event ID stored
        #      in a dictionary that maps repositories to their most recently added
        #      event ID, then update the dictionary's value and return the previously
        #      stored event ID
        #   3. If the synchronized function's response indicates that values need to be
        #      stored, begin storing values from the current highest event ID returned
        #      by the HTTP request and stop before adding the event ID that was returned
        #      by the synchronized function.
        #
        @@semaphore.synchronize do
          r.each do |e|
            # Save to MongoDB, if it is not there yet
            if settings.mongo['events'].find('id' => e["id"]).count == 0
              settings.mongo['events'].insert_one(e)

              # Publish to RabbitMQ
              key = "evt.#{e['type']}"
              settings.rabbit.publish e["id"], :persistent => true, :routing_key => key
              settings.rabbit.publish e["id"], :persistent => true, :routing_key => "bot.#{key}"
              settings.rabbit.publish "#{key} #{e["id"]}", :persistent => true, :routing_key => "log"
              settings.rabbit.publish e["id"], :persistent => true, :routing_key => "evt.Flow"
              puts "#{event['repository']['full_name']}: Adding event to mongo with id: #{e["id"]}\r\n"
            else
              puts "#{event['repository']['full_name']}: Finished grabbing all new events"
              return
            end
          end
        end

        page += 1
      end
      rescue Exception => e
        print e
    end
  end

  def verify_signature(payload_body)
    signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['SECRET_KEY'], payload_body)

    if Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
      return true
    else
      return false
    end
  end

end