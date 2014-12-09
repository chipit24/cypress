## look at https://github.com/angular/angular.js/blob/master/src/ngScenario/browserTrigger.js
## for some references on creating simulated events

## make this a global to allow attaching / overriding
window.Cypress = do ($, _) ->

  ngPrefixes = ['ng-', 'ng_', 'data-ng-', 'x-ng-']

  ## should attach these commands as defaultMethods and allow them
  ## to be configurable
  commands =
    inspect: ->
      @prop("inspect", true)

    url: ->
      @action "location", "href"

    filter: (fn) ->
      unless @prop("subject") and _.isElement(@prop("subject")[0])
        @throwErr("Cannot call .filter() without first finding an element")

      @prop("subject").filter(fn)

    ## add an array of jquery methods
    eq: ->

    ## allow the user to choose whether the confirmation
    ## message returns true or false.  need to patch
    ## window.confirm and store the last confirm message
    ## so we can async respond to it?
    confirm: (bool = true) ->

    ## saves the current subject as an alias
    save: (str) ->
      @alias str, @prop("subject")

    noop: (obj) -> obj

    ng: (type, selector, options = {}) ->
      ## ng needs to be refactored to use .find
      ## its very close to it, but not exactly the same
      ## so we end up duplicating the retry code

      _.defaults options,
        df: $.Deferred()
        retry: false
        timeout: 1000
        total: 0

      if options.total >= options.timeout
        options.df.reject("Timed out trying to find element: #{selector}")

      switch type
        when "model"
          _.each ngPrefixes, (prefix) =>
            @findByModel(options, prefix, selector)
        when "repeater"
          _.each ngPrefixes, (prefix) =>
            @findByRepeater(options, prefix, selector)
        when "binding"
          @findByBinding(options, selector)

      if options.df.state() is "pending"
        options.total += 50

        @delay =>
          @invoke(@prop("current"), type, selector, options)
        , 50

      options.df

    location: (key) ->
      currentUrl = window.location.toString()
      remoteUrl  = @$remoteIframe.prop("contentWindow").location.toString()
      remoteOrigin = @config("remoteOrigin")

      location = Cypress.location(currentUrl, remoteUrl, remoteOrigin)

      if key
        ## use existential here because we only want to throw
        ## on null or undefined values (and not empty strings)
        location[key] ?
          @throwErr("Location object does have not have key: #{key}")
      else
        location

    first: ->
      unless @prop("subject") and _.isElement(@prop("subject")[0])
        @throwErr("Cannot call .first() without first finding an element")

      @prop("subject").first()

    click: ->
      ## if subject is an anchor link then artificially
      ## add a delay of 100ms because the unload event
      ## may be firing async (soon)
      ## else just normally set a 10ms delay because clicking
      ## will generally cause some kind of DOM mutation which
      ## helps with async issues
      ## we should automatically invoke @each("click") for every
      ## member of the subject, so it logs out each one
      clicks = $.Deferred()

      dfs = []

      click = (index) =>
        el = @prop("subject").get(index)

        ## resolve the outer clicks deferred with our subject again
        return clicks.resolve(@prop("subject")) if not el

        el.click()

        wait = if $(el).is("a") then 100 else 10

        @delay dfs[index].resolve, wait# * 50

      @prop("subject").each (index, el) ->
        df = $.Deferred()
        df.done -> click(index + 1)
        dfs.push(df)

      click(0)

      return clicks

    eval: (code, options = {}) ->
      _.defaults options,
        timeout: 15000

      df = $.Deferred()

      ## obviously this needs to be moved to a separate method
      timeout = @prop("runnable").timeout()
      @prop("runnable").timeout(options.timeout)

      xhr = $.getJSON("/eval", {code: code}).done (response) =>
        @prop("runnable").timeout(timeout)

        resp = if response.obj then JSON.parse(response.obj) else response.text

        # @alias(options.store, resp) if options.store

        df.resolve resp

      @prop "xhr", xhr

      df

    visit: (url, options = {}) ->
      options.rootUrl = @config("rootUrl")

      partial = _(@).pick "$remoteIframe", "channel", "contentWindow"
      partial.runnable = @prop("runnable")
      Eclectus.patch partial
      Ecl.visit(url, options)

    ## thens can return more "thenables" which are not resolved
    ## until they're 'really' resolved, so naturally this API
    ## supports nesting promises
    then: (fn) ->
      ## if this is the very last command we know its the 'then'
      ## called by mocha.  in this case, we need to defer its
      ## fn callback else we will not properly finish the run
      ## of our commands, which ends up duplicating multiple commands
      ## downstream.  this is because this fn callback forces mocha
      ## to continue synchronously onto tests (if for instance this
      ## 'then' is called from a hook) - by defering it, we finish
      ## resolving our deferred.
      if not @prop("current").next and @prop("current").args.length is 2
        return @prop("next", fn)

      ## we need to wrap this in a try-catch still (even though we're
      ## using bluebird) because we want to handle the return by
      ## allow the 'then' to change the subject to the return value
      ## if its a non null/undefined value else to return the subject
      try
        ret = fn.call @prop("runnable").ctx, @prop("subject")

        ## then will resolve with the fn's
        ## return or just pass along the subject
        return ret ? @prop("subject")
      catch e
        throw e

    within: (selector, fn) ->

    options: (options = {}) ->
      ## change things like pauses in between commands
      ## the max timeout per command
      ## or anything else here...

    debug: ->
      console.log "\n%c------------------------Cypress Command Info------------------------", "font-weight: bold;"
      _.each ["options", "subject", "runnable", "queue", "index"], (item) =>
        console.log "#{item}: ", (@prop(item) or @[item])
      debugger

    pause: (int) ->
      int ?= 1e9

      runnable = @prop("runnable")
      prevTimeout = runnable.timeout()
      runnable.timeout(1e9)

      df = $.Deferred()

      @delay ->
        runnable.timeout(prevTimeout)
        df.resolve()
      , int

      df

    find: (selector, alias, options = {}) ->
      ## this is not properly calculating the timeout time
      ## needs to take into account Date - time
      options = if _.isObject(alias) then alias else options

      ## bail if our deferred has a state other than pending
      return if options.df and options.df.state() isnt "pending"

      _.defaults options,
        df: $.Deferred()
        retry: true
        timeout: 1000 ## this should not be hard coded here
        total: 0

      if options.total >= options.timeout
        options.df.reject("Timed out trying to find element: #{selector}")

      $el = @$(selector)

      ## return the $el immediately if we've set not to retry
      ## or we found an element
      if $el.length or not options.retry
        options.df.resolve($el)
      else
        ## think about using @retry here to abstract away
        ## the delay + invocation + options.total increment
        options.total += 50

        @delay =>
          @invoke(@prop("current"), selector, alias, options)
        , 50

      return options.df

    type: (sequence, options = {}) ->
      unless @prop("subject") and _.isElement(@prop("subject")[0])
        @throwErr("Cannot call .type() without first finding an element")

      _.extend options,
        sequence: sequence

      @prop("subject").simulate "key-sequence", options

    clear: ->
      unless @prop("subject") and _.isElement(@prop("subject")[0])
        @throwErr("Cannot call .clear() without first finding an element")

      ## on input, selectall then del so it fires all appropriate key events
      ## on select, clear its selected option
      if @prop("subject").is("input,textarea")
        @action "type", "{selectall}{del}"

      return @prop("subject")

    select: (valueOrText) ->
      unless @prop("subject") and _.isElement(@prop("subject")[0])
        @throwErr("Cannot call .select() without first finding an element")

      ## if @prop("subject") is a <select> el assume we are filtering down its
      ## options to a specific option first by value and then by text
      ## we'll throw errors if more than one is found AND the select
      ## element is multiple=multiple

      ## if the subject isn't a <select> then we'll check to make sure
      ## this is an option
      ## if this is multiple=multiple then we'll accept an array of values
      ## or texts and clear the previous selections which matches jQuery's
      ## behavior

      if @prop("subject").is("select")
        ## normalize valueOrText if its not an array
        valueOrText = [].concat(valueOrText)
        multiple    = @prop("subject").prop("multiple")

        values  = []
        options = @prop("subject").children().map (index, el) ->
          ## push the value in values array if its
          ## found within the valueOrText
          value = el.value
          values.push(value) if value in valueOrText

          ## return the elements text + value
          {
            value: value
            text: $(el).text()
          }

        ## if we couldn't find anything by value then attempt
        ## to find it by text and insert its value into values arr
        if not values.length
          _.each options.get(), (obj, index) ->
            values.push(obj.value) if obj.text in valueOrText

        ## if we didnt set multiple to true and
        ## we have more than 1 option to set then blow up
        if not multiple and values.length > 1
          @throwErr("Found more than one option that was matched by value or text: #{valueOrText.join(", ")}")

        @prop("subject").val(values)

        ## yup manually create this change event
        ## 1.6.5. HTML event types
        ## scroll down the 'change'
        event = document.createEvent("HTMLEvents")
        event.initEvent("change", true, false)

        @prop("subject").each (index, el) ->
          el.dispatchEvent(event)

    wait: (msOrFn, options = {}) ->
      msOrFn ?= 1e9

      switch
        when _.isNumber(msOrFn)
          ## increase the timeout by the delta
          @_timeout(msOrFn, true)
          return Promise.delay(msOrFn)

        when _.isFunction(msOrFn)
          fn = msOrFn

          try
            ## invoke fn and make sure its not strictly false
            options.value = fn.call(@prop("runnable").ctx, @prop("subject"))
            return @prop("subject") if options.value
          catch e
            return @retry(e, fn, options)

          ## retry outside of the try / catch block because
          ## if retry throws errors we want those to bubble
          return @retry(null, fn, options) if not options.value

        else
          @throwErr "wait() must be invoked with either a number or a function!"

  class Cypress
    queue: []

    constructor: (@options = {}) ->
      @props   = {}
      @aliases = {}

      _.defaults @options,
        commandTimeout: 2000
        delay: 0 ## whether there is a delay in between commands

    unregister: ->
      @props   = {}
      @aliases = {}

      return @

    prop: (key, val) ->
      if _.isUndefined(val)
        @props[key]
      else
        @props[key] = val

    ## global options applicable to all cy instances
    ## and restores
    options: (options = {}) ->

    isReady: (bool = true, event) ->
      if bool
        ## we set recentlyReady to true
        ## so we dont accidently set isReady
        ## back to false in between commands
        ## which are async
        @log "Ready due to: #{event}", "success"
        @prop("recentlyReady", true)

        if ready = @prop("ready")
          ready.promise.then =>
            @trigger "ready", true

        return ready?.resolve()

      ## if we already have a ready object and
      ## its state is pending just leave it be
      ## and dont touch it
      return if @prop("ready") and @prop("ready").promise.isPending()

      ## else set it to a deferred object
      @log "No longer ready due to: #{event}", "warning"

      @trigger "ready", false

      ## using sync deferred here because we really
      ## need it to be sync, not async
      @prop "ready", Promise.pending()

    ## simulates the deferred interface with BlueBird
    _deferred: ->
      pending = Promise.pending()
      pending.promise.cancellable()

      ## tell it expliticly we're done
      ## adding handlers because we dont want
      ## notifications about unhandled error messages
      pending.promise.caught((err) ->).done()
      pending

    run: ->
      ## start at 0 index if we dont have one
      index = @prop("index") ? @prop("index", 0)

      queue = @queue[index]

      runnable = @prop("runnable")

      @group(runnable.group)

      ## if we're at the very end
      if not queue

        ## trigger end event
        @trigger("end")

        ## and we should have a next property which
        ## holds mocha's .then callback fn
        if next = @prop("next")
          next()

        return @

      ## store the previous timeout
      prevTimeout = runnable.timeout()

      ## prior to running set the runnables
      ## timeout to 30s. this is useful
      ## because we may have to wait to begin
      ## running such as the case in angular
      runnable.timeout(30000)

      run = =>
        ## bail if we've changed runnables by the
        ## time this resolves
        return if @prop("runnable") isnt runnable

        @trigger "command:start", queue

        ## reset the timeout to what it used to be
        runnable.timeout(prevTimeout)

        promise = @set(queue, @queue[index - 1], @queue[index + 1]).then =>
          ## each successful command invocation should
          ## always reset the timeout for the current runnable
          runnable.resetTimeout()

          ## mutate index by incrementing it
          ## this allows us to keep the proper index
          ## in between different hooks like before + beforeEach
          ## else run will be called again and index would start
          ## over at 0
          @prop("index", index += 1)

          @trigger "command:end"

          @defer => @run()

          ## must have this empty return here else we end up creating
          ## additional .then callbacks due to bluebird chaining
          return null

        .catch Promise.CancellationError, (err) =>
          @cancel(err)

          ## need to signify we're done our promise here
          ## so we cannot chain off of it, or have bluebird
          ## accidentally chain off of the return value
          return err

        .catch (err) =>
          @fail(err)

          return err
        ## signify we are at the end of the chain and do not
        ## continue chaining anymore
        # promise.done()

        @prop "promise", promise

        @trigger "set"

      ## automatically defer running each command in succession
      ## so each command is async
      @defer =>
        angular = @$remoteIframe.prop("contentWindow").angular

        if angular and angular.getTestability
          root = @$("[ng-app]").get(0)
          run = _.bind(run, @)
          angular.getTestability(root).whenStable(run)
        else
          run()

    clearTimeout: (id) ->
      clearTimeout(id) if id
      return @

    alias: (name, value) ->
      @aliases[name] = value
      @

    get: (name) ->
      alias = @aliases[name]
      return alias unless _.isUndefined(alias)

      ## instead of returning a function here and setting this
      ## invoke property, we should just convert this to a deferred
      ## and then during the actual save we should find out anystanding
      ## 'get' promises that match the name and then resolve them.
      ## the problem with this is we still need to run this anonymous
      ## function to check to see if we have an alias by that name
      ## else our alias will never resolve (if save is never called
      ## by this name argument)
      fn = =>
        @aliases[name] or
          @throwErr("No alias was found by the name: #{name}")
      fn._invokeImmediately = true
      fn

    storeHref: ->
      ## we are using href and stripping out the hash because
      ## hash changes do not cause full page refreshes
      ## however, i believe this will completely barf when
      ## JS users are using pushstate since there is no hash
      ## TODO. need to listen to pushstate events here which
      ## will act as the isReady() the same way load events do
      location = @action("location")
      @href    = location.href.replace(location.hash, "")

    hrefChanged: ->
      location = @action("location")
      @href isnt location.href.replace(location.hash, "")

    _timeout: (ms, delta = false) ->
      runnable = @prop("runnable")
      @throwErr("Cannot call .timeout() without a currently running test!") if not runnable
      if ms
        ## if delta is true then we add (or subtract) from the
        ## runnables current timeout instead of blanketingly setting it
        ms = if delta then runnable.timeout() + ms else ms
        runnable.timeout(ms)
        return @
      else
        runnable.timeout()

    set: (obj, prev, next) ->
      obj.prev = prev
      obj.next = next

      @prop("current", obj)

      @invoke2(obj)

    invoke2: (obj, args...) ->
      promise = if @prop("ready")
        Promise.resolve @prop("ready").promise
      else
        Promise.resolve()

      ## break the promise chain and return the outer promise for cancellation
      ## reasons
      promise.cancellable().then =>
        @trigger "invoke:start", obj

        @log obj

        ## store our current href before invoking the next command
        @storeHref()

        @prop "nestedIndex", @prop("index")

        ## allow the invoked arguments to be overridden by
        ## passing them in explicitly
        ## else just use the arguments the command was
        ## originally created with
        if args.length then args else obj.args

      ## allow promises to be used in the arguments
      ## and wait until they're all resolved
      .all(args)

      .then (args) =>
        ## if the first argument is a function and it has an _invokeImmediately
        ## property that means we are supposed to immediately invoke
        ## it and use its return value as the argument to our
        ## current command object
        if _.isFunction(args[0]) and args[0]._invokeImmediately
          args[0] = args[0].call(@)

        ## we cannot pass our cypress instance back into
        ## bluebird else it will create a thenable which
        ## is never resolved
        ret = obj.fn.apply(obj.ctx, args)
        if ret is @ then @prop("subject") else ret

      .then (subject, options = {}) =>
        # if we havent become recently ready and unless we've
        # explicitly disabled checking for location changes
        # and if our href has changed in between running the commands then
        # then we're no longer ready to proceed with the next command
        if @prop("recentlyReady") is null and options.checkLocation isnt false
          @isReady(false, "href changed") if @hrefChanged()

        ## reset the nestedIndex back to null
        @prop("nestedIndex", null)

        ## also reset recentlyReady back to null
        @prop("recentlyReady", null)

        ## return the prop subject
        @prop("subject", subject)

        @trigger "invoke:end", obj

        return subject

    throwErr: (err) ->
      if _.isString(err)
        err = new Error(err)

      throw err

    cancel: (err) ->
      obj = @prop("current")
      @log {name: "Cancelled: #{obj.name}", args: err.message}, "danger"
      @trigger "cancel", obj

    fail: (err) ->
      obj = @prop("current")
      @log {name: "Failed: #{obj.name}", args: err.message}, "danger"
      @runner.uncaught(err)
      @trigger "fail", err

    retry: (err, fn, options) ->
      _.defaults options,
        runnableTimeout: @_timeout()
        start: new Date
        interval: 50

      ## we always want to make sure we timeout before our runnable does
      ## so take its current timeout, subtract the total time its already
      ## been running and add the options.interval for a tiny bit of padding
      options.timeout ?= options.runnableTimeout - (new Date - @prop("runnable").startedAt + options.interval)

      ## we calculate the total time we've been retrying
      ## so we dont exceed the runnables timeout
      total = (new Date - options.start)

      ## if our total exceeds the timeout OR the total + the interval
      ## exceed the runnables timeout, then bail
      if total >= options.timeout or (total + options.interval >= options.runnableTimeout)
        err ?= new Error options.value
        err.message = "Timed out retrying. The final value was: " + err.message
        @throwErr(err)

      Promise.delay(options.interval).then =>
        @trigger "retry", fn, options

        ## should check here to make sure we have a .prev
        ## and if not we should throwErr
        @invoke2(@prop("current").prev).then =>
          @invoke2(@prop("current"), fn, options)

    action: (name, args...) ->
      commands[name].apply(@, args)

    defer: (fn) ->
      @delay(fn, 0)

    delay: (fn, ms) ->
      @clearTimeout(@prop("timerId"))
      @prop "timerId", _.delay(fn, ms)

    findByBinding: (options, binding) ->
      options = _(options).clone()

      df = options.df

      selector = ".ng-binding"

      angular = @$remoteIframe.prop("contentWindow").angular

      options.df = $.Deferred()
      options.df.done ($elements) ->
        filtered = $elements.filter (index) ->
          dataBinding = angular.element(@).data("$binding")

          if dataBinding
            bindingName = dataBinding.exp or dataBinding[0].exp or dataBinding
            return binding in bindingName

        if filtered.length
          df.resolve(filtered)

      @action("find", selector, null, options)

    findByRepeater: (options, prefix, repeater) ->
      options = _(options).clone()

      df = options.df

      attr = prefix + "repeat"
      selector = "[" + attr + "]"

      options.df = $.Deferred()
      options.df.done ($elements) ->
        filtered = $elements.filter (index) ->
          _.str.include($(@).attr(attr), repeater)

        if filtered.length
          df.resolve(filtered)

      @action("find", selector, null, options)

    findByModel: (options, prefix, model) ->
      options = _(options).clone()

      df = options.df

      selector = "[" + prefix + "model='" + model + "']"

      options.df = $.Deferred()
      options.df.done ($elements) ->
        df.resolve($elements) if $elements.length

      @action("find", selector, null, options)

    hook: (name) ->
      return if not @prop("inspect")

      return console.groupEnd() if not name

      console.group(name)

    group: (name) ->
      ## bail if we're not in inspect mode
      return if not @prop("inspect") or _.isUndefined(name)

      ## end the group if name is explicitly false
      return console.groupEnd() if name is false

      ## bail if we already have a _group set
      return if @_group

      ## set the _group
      @_group = name

      ## start a group by the name
      console.group(name)

    log: (obj, type) ->
      return if not @prop("inspect")

      color = {
        success: "#46B848"
        info:    "#5FC0DD"
        warning: "#D99538"
        danger:  "#D7514F"
      }[type] or "blue"

      if _.isString(obj)
        obj = {name: obj, args: ""}

      console.log "%c#{obj.name}", "color: #{color}", _.truncate(obj.args, 50)

    enqueue: (key, fn, args, options) ->
      @clearTimeout @prop("runId")

      obj = {name: key, ctx: @, fn: fn, args: args, options: options}

      ## if we have a nestedIndex it means we're processing
      ## nested commands and need to splice them into the
      ## index past the current index as opposed to
      ## pushing them to the end we also dont want to
      ## reset the run defer because splicing means we're
      ## already in a run loop and dont want to create another!
      ## we also reset the .next property to properly reference
      ## our new obj
      if nestedIndex = @prop("nestedIndex")
        @queue[nestedIndex].next = obj
        @queue.splice (@prop("nestedIndex", nestedIndex += 1)), 0, obj
      else
        @queue.push(obj)
        @prop "runId", @defer _(@run).bind(@)

      return @

    $: (selector) ->
      new $.fn.init(selector, @$remoteIframe.prop("contentWindow").document)

    _: _

    @commands = commands

    @add = (key, options, fn) ->
      ## if fn was omitted then we
      ## assume fn is the options
      if _.isUndefined(fn)
        fn = options
        options = {}

      @commands[key] = fn

      _.defaults options,
        logChildren: true
        log: true

      ## need to pass the options into inject here
      @inject(key, fn, options)

    @inject = (key, fn, options = {}) ->
      Cypress.prototype[key] = (args...) ->
        @enqueue(key, fn, args, options)

    ## remove all of the partialed functions from Cypress prototype
    @unpatch = (fns) ->
      fns = _(commands).keys().concat("sandbox")
      _.each (fns), (fn, obj) ->
        delete Cypress.prototype[fn]

    @abort = ->
      @cy.$remoteIframe?.off("submit unload load")
      @cy.isReady(false, "abort")
      @cy.prop("xhr")?.abort()
      @cy.prop("runnable")?.clearTimeout()

      promise = @cy.prop("promise")
      promise?.cancel()

      Promise.resolve(promise).then => @restore()

    ## restores cypress after each test run by
    ## removing the queue from the proto and
    ## removing additional own instance properties
    @restore = ->
      @cy.clearTimeout @cy.prop("runId")
      @cy.clearTimeout @cy.prop("timerId")

      Cypress.prototype.queue = []

      ## remove any outstanding groups
      ## for any open hooks and runnables
      @cy.group(false)
      @cy.group(false)

      ## remove any event listeners
      @cy.off()
      @cy.stopListening()

      ## removes any registered props from the
      ## instance
      @cy.unregister()

      return @

    ## removes channel, remoteIframe, contentWindow
    ## from the cypress instance
    @stop = ->
      @abort().then =>
        _.extend @cy,
          runner:        null
          remoteIframe:  null
          channel:       null
          config:        null

        window.cy = @cy = null

    ## sets the runnable onto the cy instance
    @set = (runnable, hook) ->
      runnable.startedAt = new Date
      @cy.hook(hook)
      @cy.prop("runnable", runnable)

    ## patches the cypress instance with contentWindow
    ## remoteIframe and channel
    ## this should be moved to an instance method and
    @setup = (runner, $remoteIframe, channel, config) ->
      ## we listen for the unload + submit events on
      ## the window, because when we receive them we
      ## tell cy its not ready and this prevents any
      ## additional invocations of any commands until
      ## its ready again (which happens after the load
      ## event)
      bindEvents = ->
        win = $($remoteIframe.prop("contentWindow"))
        win.off("submit").on "submit", (e) =>
          ## if we've prevented the default submit action
          ## without stopping propagation, we will still
          ## receive this event even though the form
          ## did not submit
          return if e.isDefaultPrevented()

          @cy.isReady(false, "submit")

        win.off("unload").on "unload", =>
          ## put cy in a waiting state now that
          ## we've unloaded
          @cy.isReady(false, "unload")

        win.get(0).confirm = (message) ->
          console.info "Confirming 'true' to: ", message
          return true

      $remoteIframe.on "load", =>
        bindEvents()
        @cy.isReady(true, "load")

      _.extend @cy,
        runner:        runner
        $remoteIframe: $remoteIframe
        channel:       channel
        config:        config

      ## anytime setup is called we immediately
      ## set cy to be ready to invoke commands
      ## this prevents a bug where we go into not
      ## ready mode due to the unload event when
      ## our tests are re-run
      @cy.isReady(true, "setup")

    @start = ->
      _.each @commands, (fn, key) =>
        @inject(key, fn)

      window.cy = @cy = new Cypress

      _.extend @cy, Backbone.Events

      ## return the class as opposed to the
      ## instance so we dont have to worry about
      ## accidentally chaining the 'then' method
      ## during tests
      return @

  return Cypress
