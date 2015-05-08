# Description
#   Rundeck integration with hubot
#
# Dependencies:
#   "underscore": "^1.6.0"
#   "strftime": "^0.8.0"
#   "xml2js": "^0.4.1"
#
# Commands:
#   hubot rundeck projects                        - Gets a list of the projects for the given server alias
#   hubut rundeck jobs [project]                  - Gets a list of all the jobs in the given project for the given server alias
#   hubot rundeck trigger [project] [job] [args]  - Triggers the given job for the given project
#   hubot rundeck status [project] [job]          - Shows the current status for the latest execution of the given job
#
# Author:
#  Liam Bennett
#  bibby (modified)

_ = require('underscore')
sys = require 'sys' # Used for debugging
Parser = require('xml2js').Parser

class Rundeck
  constructor: (@robot) ->
    @logger = @robot.logger

    @baseUrl = "#{process.env.HUBOT_RUNDECK_URL}/api/12"
    @authToken = process.env.HUBOT_RUNDECK_TOKEN
    @adminRole = "rundeck_admin"

    @headers =
      "Accept": "application/xml"
      "Content-Type": "application/xml"
      "X-Rundeck-Auth-Token": "#{@authToken}"

    @plainTextHeaders =
      "Accept": "text/plain"
      "Content-Type": "text/plain"
      "X-Rundeck-Auth-Token": "#{@authToken}"

  jobs: (project) -> new Jobs(@, project)
  projects: -> new Projects(@)
  executions: (job) -> new Executions(@, job)

  getOutput: (url, cb) ->
    @robot.http("#{@baseUrl}/#{url}").headers(@plainTextHeaders).get() (err, res, body) =>
      if err?
        @logger.err JSON.stringify(err)
      else
        cb body

  get: (url, cb) ->
    @logger.debug url
    parser = new Parser()

    @robot.http("#{@baseUrl}/#{url}").headers(@headers).get() (err, res, body) =>
      console.log "#{@baseUrl}/#{url}"
      if err?
        @logger.error JSON.stringify(err)
      else
        parser.parseString body, (e, json) ->
          cb json

  challenge: (msg) ->
    if @robot.auth.hasRole(msg.envelope.user, @adminRole)
      return true
    msg.send(msg.envelope.user.name + " not authorized.")
    return false

class Projects
  constructor: (@rundeck) ->
    @logger = @rundeck.logger

  list: (cb) ->
    projects = []
    @rundeck.get "projects", (results) ->
      for project in results.projects.project
        projects.push new Project(project)

      cb projects

class Project
  constructor: (data) ->
    @name = data.name[0]
    @description = data.description[0]

  formatList: ->
    "#{@name} - #{@description}"

class Jobs
  constructor: (@rundeck, @project) ->
    @logger = @rundeck.logger

  list: (cb) ->
    jobs = []
    @rundeck.get "project/#{@project}/jobs", (results) ->
      for job in results.jobs.job
        jobs.push new Job(job)

      cb jobs

  find: (name, cb) ->
    @list (jobs) =>
      job = _.findWhere jobs, { name: name }
      if job
        cb job
      else
        cb false

  run: (name, args, cb) ->
    @find name, (job) =>
      if job
        uri = "job/#{job.id}/run"
        if args?
          uri += "?argString=#{args}"

        @rundeck.get uri, (results) ->
          cb job, results
      else
        cb null, false

class Job
  constructor: (data) ->
    @id = data["$"].id
    @name = data.name[0]
    @description = data.description[0]
    @group = data.group[0]
    @project = data.project[0]

  formatList: ->
    "#{@name} - #{@description}"

class Executions
  constructor: (@rundeck, @job) ->
    @logger = @rundeck.logger

  list: (cb) ->
    executions = []
    @rundeck.get "job/#{@job.id}/executions", (results) ->
      for execution in results.executions.execution
        exec = new Execution(execution)
        executions.push exec

      cb executions

class Execution
  constructor: (@data) ->
    @id = data["$"].id
    @href = data["$"].href
    @status = data["$"].status

  formatList: ->
    "#{@id} - #{@status} - #{@href}"

module.exports = (robot) ->
  logger = robot.logger
  rundeck = new Rundeck(robot)

  robot.respond /rundeck projects/i, (msg) ->
    if not rundeck.challenge msg
      return

    rundeck.projects().list (projects) ->
      if projects.length > 0
        for project in projects
          msg.send project.formatList()
      else
        msg.send "No rundeck projects found."

  #hubot rundeck MyProject jobs
  robot.respond /rundeck jobs (\w+)/i, (msg) ->
    if not rundeck.challenge msg
      return

    project = msg.match[1]

    rundeck.jobs(project).list (jobs) ->
      if jobs.length > 0
        for job in jobs
          msg.send job.formatList()
      else
        msg.send "No jobs found for rundeck #{project}"

  #hubot rundeck trigger MyProject my-job <optional args>
  robot.respond /rundeck trigger (\w+) (\w+)\s?(.*)/i, (msg) ->
    if not rundeck.challenge msg
      return

    project = msg.match[1]
    name = msg.match[2]
    args = msg.match[3]

    rundeck.jobs(project).run name, args, (job, results) ->
      if job
        msg.send "Successfully triggered a run for the job: #{name}"
      else
        msg.send "Could not execute rundeck job \"#{name}\"."

  robot.respond /rundeck status (\w+) (\w+)/i, (msg) ->
    if not rundeck.challenge msg
      return

    project = msg.match[1]
    name = msg.match[2]

    rundeck.jobs(project).find name, (job) ->
      if job
        rundeck.executions(job).list (executions) ->
          if executions.length > 0
            keys = []
            for item in executions
              keys.push item.id
            key = keys.sort()[keys.length - 1]
            for execution in executions
              if execution.id == key
                msg.send execution.formatList()
          else
            msg.send "No executions found"
      else
        msg.send "Could not find rundeck job \"#{name}\"."