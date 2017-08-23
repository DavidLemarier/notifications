{Notification, CompositeDisposable} = require 'soldat'
fs = require 'fs-plus'
StackTraceParser = null
NotificationElement = require './notification-element'

Notifications =
  isInitialized: false
  subscriptions: null
  duplicateTimeDelay: 500
  lastNotification: null

  activate: (state) ->
    CommandLogger = require './command-logger'
    CommandLogger.start()
    @subscriptions = new CompositeDisposable

    @addNotificationView(notification) for notification in soldat.notifications.getNotifications()
    @subscriptions.add soldat.notifications.onDidAddNotification (notification) => @addNotificationView(notification)

    @subscriptions.add soldat.onWillThrowError ({message, url, line, originalError, preventDefault}) ->
      if originalError.name is 'BufferedProcessError'
        message = message.replace('Uncaught BufferedProcessError: ', '')
        soldat.notifications.addError(message, dismissable: true)

      else if originalError.code is 'ENOENT' and not /\/soldat/i.test(message) and match = /spawn (.+) ENOENT/.exec(message)
        message = """
          '#{match[1]}' could not be spawned.
          Is it installed and on your path?
          If so please open an issue on the package spawning the process.
        """
        soldat.notifications.addError(message, dismissable: true)

      else if not soldat.inDevMode() or soldat.config.get('notifications.showErrorsInDevMode')
        preventDefault()

        # Ignore errors with no paths in them since they are impossible to trace
        if originalError.stack and not isCoreOrPackageStackTrace(originalError.stack)
          return

        options =
          detail: "#{url}:#{line}"
          stack: originalError.stack
          metadata: originalError.metadata
          dismissable: true
        soldat.notifications.addFatalError(message, options)

    @subscriptions.add soldat.commands.add 'soldat-workspace', 'core:cancel', ->
      notification.dismiss() for notification in soldat.notifications.getNotifications()

    if soldat.inDevMode()
      @subscriptions.add soldat.commands.add 'soldat-workspace', 'notifications:toggle-dev-panel', -> Notifications.togglePanel()
      @subscriptions.add soldat.commands.add 'soldat-workspace', 'notifications:trigger-error', ->
        try
          abc + 2 # nope
        catch error
          options =
            detail: error.stack.split('\n')[1]
            stack: error.stack
            dismissable: true
          soldat.notifications.addFatalError("Uncaught #{error.stack.split('\n')[0]}", options)

  deactivate: ->
    @subscriptions.dispose()
    @notificationsElement?.remove()
    @notificationsPanel?.destroy()

    @subscriptions = null
    @notificationsElement = null
    @notificationsPanel = null

    @isInitialized = false

  initializeIfNotInitialized: ->
    return if @isInitialized

    @subscriptions.add soldat.views.addViewProvider Notification, (model) ->
      new NotificationElement(model)

    @notificationsElement = document.createElement('soldat-notifications')
    soldat.views.getView(soldat.workspace).appendChild(@notificationsElement)

    @isInitialized = true

  togglePanel: ->
    if @notificationsPanel?
      if Notifications.notificationsPanel.isVisible()
        Notifications.notificationsPanel.hide()
      else
        Notifications.notificationsPanel.show()
    else
      NotificationsPanelView = require './notifications-panel-view'
      Notifications.notificationsPanelView = new NotificationsPanelView
      Notifications.notificationsPanel = soldat.workspace.addBottomPanel(item: Notifications.notificationsPanelView.getElement())

  addNotificationView: (notification) ->
    return unless notification?
    @initializeIfNotInitialized()
    return if notification.wasDisplayed()

    if @lastNotification?
      # do not show duplicates unless some amount of time has passed
      timeSpan = notification.getTimestamp() - @lastNotification.getTimestamp()
      unless timeSpan < @duplicateTimeDelay and notification.isEqual(@lastNotification)
        @notificationsElement.appendChild(soldat.views.getView(notification).element)
    else
      @notificationsElement.appendChild(soldat.views.getView(notification).element)

    notification.setDisplayed(true)
    @lastNotification = notification

isCoreOrPackageStackTrace = (stack) ->
  StackTraceParser ?= require 'stacktrace-parser'
  for {file} in StackTraceParser.parse(stack)
    if file is '<embedded>' or fs.isAbsolute(file)
      return true
  false

module.exports = Notifications
