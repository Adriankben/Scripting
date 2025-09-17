<#
.SYNOPSIS
    Collects specific event log entries from System and Application logs within a given time frame.
.DESCRIPTION
    Filters events by event IDs and time window, then outputs the results in a formatted table.
.PARAMETER systemEventIDs
    Array of event IDs to filter for.
.PARAMETER daysOfLogs
    Number of past days to include in the event search.
#>

###### Modify values to fit your needs ######
$systemEventIDs = 12, 13, 19, 21, 43, 1074, 1040, 1033
$daysOfLogs = 1
############################################

# Calculate the cutoff time to filter recent events
$cutoffTime = (Get-Date).AddDays(-$daysOfLogs)

# Retrieve filtered events from System and Application logs
$filter = @{
    LogName   = @('System', 'Application')
    Id        = $systemEventIDs
    StartTime = $cutoffTime
}

try {
    $systemEvents = Get-WinEvent -FilterHashtable $filter | 
                    Select-Object TimeCreated, Id, Message

    if ($systemEvents) {
        # Output events in table format, wrapped for readability
        $systemEvents | Format-Table TimeCreated, Id, Message -Wrap -AutoSize
    } else {
        Write-Output "No events found matching criteria."
    }
} catch {
    Write-Error "Error retrieving events: $_"
}

Exit 0
