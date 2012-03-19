#!/usr/bin/env ruby
#
# Copyright 2012 Georgios Gousios <gousiosg@gmail.com>
#
# Redistribution and use in source and binary forms, with or
# without modification, are permitted provided that the following
# conditions are met:
#
#   1. Redistributions of source code must retain the above
#      copyright notice, this list of conditions and the following
#      disclaimer.
#
#   2. Redistributions in binary form must reproduce the above
#      copyright notice, this list of conditions and the following
#      disclaimer in the documentation and/or other materials
#      provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
# USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require 'rubygems'
require 'yaml'
require 'amqp'
require 'eventmachine'
require 'github-analysis'
require 'json'
require 'mongo'

GH = GithubAnalysis.new

# Graceful exit
Signal.trap('INT') { AMQP.stop { EM.stop } }
Signal.trap('TERM') { AMQP.stop { EM.stop } }

events = GH.events_col
counter = 0

# Selectively load event types
evt_type = ARGV.shift

valid_types = ["CommitComment", "CreateEvent", "DeleteEvent", "DownloadEvent",
"FollowEvent", "ForkEvent", "ForkApplyEvent", "GistEvent", "GollumEvent",
"IssueCommentEvent", "IssuesEvent", "MemberEvent", "PublicEvent",
"PullRequestEvent", "PushEvent", "TeamAddEvent", "WatchEvent"]

q = if evt_type.nil?
  {}
else
  if valid_types.include? evt_type
    {"type" => evt_type}
  else
    puts "No valid event type #{evt_type}"
    puts "Valid event types are :"
    valid_types.each{|x| puts "\t", x, "\n"}
    exit 1
  end
end

AMQP.start(:host => GH.settings['amqp']['host'],
           :port => GH.settings['amqp']['port'],
           :username => GH.settings['amqp']['username'],
           :password => GH.settings['amqp']['password']) do |connection|

  channel = AMQP::Channel.new(connection, :prefetch => 5)
  exchange = channel.topic(GH.settings['amqp']['exchange'],
                          :durable => true, :auto_delete => false)

  events.find(q).each do |e|
    msg = e.json
    key = "evt.%s" % e['type']
    exchange.publish msg, :persistent => true, :routing_key => key
    counter += 1
    print "\r #{counter} events loaded"
  end

  AMQP.stop
end

# vim: set sta sts=2 shiftwidth=2 sw=2 et ai :
