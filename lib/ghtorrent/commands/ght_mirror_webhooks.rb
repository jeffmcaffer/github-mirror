class GHTMirrorWebhooks < GHTMirrorEvents
  def watch(exchange)
    channel = exchange.channel
    queue = channel.queue("Events", {:durable => true})\
                          .bind(exchange, :routing_key => "evt.Event")
    info "Binding Events handler to routing key evt.Event"
    queue.subscribe(:manual_ack => true) do |headers, properties, msg|
      start = Time.now
      begin
        retrieve(exchange, msg)
        channel.acknowledge(headers.delivery_tag, false)
        info "Success dispatching event. Repo: #{msg}, Time: #{Time.now.to_ms - start.to_ms} ms"
      rescue StandardError => e
        # Give a message a chance to be reprocessed
        if headers.redelivered?
          warn "Error dispatching event. Repo: #{msg}, Time: #{Time.now.to_ms - start.to_ms} ms"
          channel.reject(headers.delivery_tag, false)
        else
          channel.reject(headers.delivery_tag, true)
        end

        STDERR.puts e
        STDERR.puts e.backtrace.join("\n")
      end
    end

    stopped = false
    while not stopped
      begin
        sleep(1)
      rescue Interrupt => _
        debug 'Exit requested'
        stopped = true
      end
    end
  end
end