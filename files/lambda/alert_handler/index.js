var https = require('https');
var util = require('util');

var CHANNEL = process.env.SLACK_CHANNEL_NAME;
var PATH = process.env.SLACK_PATH;
var ACCOUNT = process.env.ACCOUNT;

exports.handler = function(message, context) {
    console.log(toString(message));
    
    var event = toCommonEvent(message);
    
    console.log(event.source, event.title, event.description);

    var postData = toSlackPost(event);

    var options = {
        method: 'POST',
        hostname: 'hooks.slack.com',
        port: 443,
        path: PATH
    };

    var req = https.request(options, function(res) {
      res.setEncoding('utf8');
      res.on('data', function (chunk) {
        context.done(null, postData);
      });
    });
    
    req.on('error', function(e) {
      console.log('problem with request: ' + e.message);
    });    

    req.write(util.format("%j", postData));
    req.end();
};

var DANGER_MESSAGES = [
    " but with errors",
    " to RED",
    "During an aborted deployment",
    "Failed to deploy application",
    "Failed to deploy configuration",
    "has a dependent object",
    "is not authorized to perform",
    "Pending to Degraded",
    "Stack deletion failed",
    "Unsuccessful command execution",
    "You do not have permission",
    "Your quota allows for 0 more running instance"];

var WARNING_MESSAGES = [
    " aborted operation.",
    " to YELLOW",
    "Adding instance ",
    "Degraded to Info",
    "Deleting SNS topic",
    "is currently running under desired capacity",
    "Ok to Info",
    "Ok to Warning",
    "Pending Initialization",
    "Removed instance ",
    "Rollback of environment"        
    ];
    
var LOW_SEVERITY = "good";
var MEDIUM_SEVERITY = "warning";
var HIGH_SEVERITY = "danger";

var LEVELS = {
    [LOW_SEVERITY]: "INFO",
    [MEDIUM_SEVERITY]: "WARNING",
    [HIGH_SEVERITY]: "ERROR"
};

function determineSnsSeverity(message) {
    for(var dangerMessagesItem in DANGER_MESSAGES) {
        if (message.indexOf(DANGER_MESSAGES[dangerMessagesItem]) != -1) {
            return HIGH_SEVERITY;
        }
    }
    
    for(var warningMessagesItem in WARNING_MESSAGES) {
        if (message.indexOf(WARNING_MESSAGES[warningMessagesItem]) != -1) {
            return MEDIUM_SEVERITY;
        }
    }        
    
    return LOW_SEVERITY;
}

function determineGuardDutySeverity(severityNumber) {
    // https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings.html#guardduty_findings-severity
    if (severityNumber >= 7.0 && severityNumber <= 8.9) {
        return HIGH_SEVERITY;
    }

    if (severityNumber >= 4.0 && severityNumber <= 6.9) {
        return MEDIUM_SEVERITY;
    }

    return LOW_SEVERITY;
}

function findingLink(region, id) {
    return `https://${region}.console.aws.amazon.com/guardduty/home?region=${region}#/findings?macros=all&fId=${id} (switch to ${ACCOUNT} to see)`;
}

function toCommonEvent(event) {
    if (event.Records[0].Sns.Subject != null) {
        var message = event.Records[0].Sns.Message;
        return {
            title: event.Records[0].Sns.Subject,
            description: message,
            severity: determineSnsSeverity(message),
            source: "SNS"
        };
    }

    if (event.Records[0].Sns.Subject == null) {
        var cloudWatchEvent = JSON.parse(event.Records[0].Sns.Message);
        if (cloudWatchEvent["detail-type"] == "GuardDuty Finding") {
            return {
                title: cloudWatchEvent.detail.title,
                description: cloudWatchEvent.detail.description + "\nSee this GuardDuty link for more details: " + findingLink(cloudWatchEvent.detail.region, cloudWatchEvent.detail.id),
                severity: determineGuardDutySeverity(cloudWatchEvent.detail.severity),
                source: "GuardDuty"
            };
        }
        return {
            title: cloudWatchEvent["detail-type"],
            description: "User performed API action of " + cloudWatchEvent.detail.eventName,
            severity: MEDIUM_SEVERITY,
            source: "GuardDuty API"
        };
    }
    
    return {
        title: 'Unidentified Event Type Received',
        description: toString(event),
        severity: LOW_SEVERITY,
        source: "UNKNOWN"
    };
}

function toString(event) {
    return JSON.stringify(event, null, 2);
}

function toSlackPost(event) {
    var post = {
        "channel": CHANNEL,
        "username": "AWS Alerts",
        "text": "*" + LEVELS[event.severity] + ":" + event.title + "*",
        "icon_emoji": ":aws:"
    };

    post.attachments = [
        {
            "color": event.severity, 
            "text": event.description
        }
    ];
    
    return post;
}