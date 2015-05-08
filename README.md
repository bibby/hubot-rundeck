hubot-rundeck
==

A Hubot script for orchestrating jobs with a [rundeck](http://www.rundeck.org/) server

*Forked* from [opentable/hubot-rundeck](https://github.com/opentable/hubot-rundeck) with the following changes:

- Authorization tokens and service urls are not exposed in the channels!
- authToken and url are set via process environment variables `HUBOT_RUNDECK_TOKEN` and `HUBOT_RUNDECK_URL`
- Consistency with parameter order -> project, job, args
- No longer supports multiple rundeck servers
- Removed anything regarding server aliasing
