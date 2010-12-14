class EventLoop
  constructor: (window)->
    window.browser.clock = 0
    timers = {}
    lastHandle = 0

    # Implements window.setTimeout using event queue
    @setTimeout = (fn, delay)->
      timer = 
        when: window.browser.clock + delay
        timeout: true
        fire: ->
          try
            if typeof fn == "function"
              fn.apply(window)
            else
              eval fn
          finally
            delete timers[handle]
      handle = ++lastHandle
      timers[handle] = timer
      handle
    # Implements window.setInterval using event queue
    @setInterval = (fn, delay)->
      timer = 
        when: window.browser.clock + delay
        interval: true
        fire: ->
          try
            if typeof fn == "function"
              fn.apply(window)
            else
              eval fn
          finally
            timer.when = window.browser.clock + delay
      handle = ++lastHandle
      timers[handle] = timer
      handle
    # Implements window.clearTimeout using event queue
    @clearTimeout = (handle)-> delete timers[handle] if timers[handle]?.timeout
    # Implements window.clearInterval using event queue
    @clearInterval = (handle)-> delete timers[handle] if timers[handle]?.interval

    # Requests on wait that cannot be handled yet: there's no event in the
    # queue, but we anticipate one (in-progress XHR request).
    waiting = []
    # Queue of events.
    queue = []

    # Queue an event to be processed by wait(). Event is a function call in the
    # context of the window.
    @queue = (event)->
      queue.push event if event
      wait() for wait in waiting
      waiting = []

    # Process all events from the queue. This method returns immediately, events
    # are processed in the background. When all events are exhausted, it calls
    # the callback with null, window; if any event fails, it calls the callback
    # with the exception.
    #
    # With one argument, that argument is the callback. With two arguments, the
    # first argument is a terminator and the last argument is the callback. The
    # terminator is one of:
    # - null -- process all events
    # - number -- process that number of events
    # - function -- called after each event, stop processing when function
    #   returns false
    #
    # Events include timeout, interval and XHR onreadystatechange. DOM events
    # are handled synchronously.
    @wait = (terminate, callback, intervals)->
      if !callback
        intervals = callback
        callback = terminate
        terminate = null
      process.nextTick =>
        if event = queue.shift()
          intervals = true
        else
          earliest = null
          for handle, timer of timers
            continue if timer.interval && intervals == false
            earliest = timer if !earliest || timer.when < earliest.when
          if earliest
            intervals = false
            event = ->
              window.browser.clock = earliest.when if window.browser.clock < earliest.when
              earliest.fire()
        if event
          try 
            event.call(window)
            if typeof terminate is "number"
              --terminate
              if terminate <= 0
                process.nextTick -> callback null, window
                return
            else if typeof terminate is "function"
              if terminate.call(window) == false
                process.nextTick -> callback null, window
                return
            @wait terminate, callback, intervals
          catch err
            callback err, window
        else if requests > 0
          waiting.push => @wait terminate, callback, intervals
        else
          callback null, window

    # Counts outstanding requests.
    requests = 0
    # Used internally for the duration of an internal request (loading
    # resource, XHR). Function is invoked with single argument (done), a
    # function to call when done processing the request.
    @request = (fn)->
      ++requests
      fn ->
        if --requests == 0
          wait() for wait in waiting
          waiting = []


# Attach event loop to window: creates new event loop and adds
# timeout/interval methods and XHR class.
exports.attach = (window)->
  eventLoop = new EventLoop(window)
  for fn in ["setTimeout", "setInterval", "clearTimeout", "clearInterval"]
    window[fn] = -> eventLoop[fn].apply(window, arguments)
  window.queue = eventLoop.queue
  window.wait = eventLoop.wait
  window.request = eventLoop.request 