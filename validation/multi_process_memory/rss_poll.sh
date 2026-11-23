#!/bin/bash
# rss_poll.sh <pattern> <logfile>: every 10 s, VmRSS of each matching process and the total, until none remain for 60 s.
pat=$1; log=$2; idle=0
while true; do
  pids=$(pgrep -f "[j]ulia.*$pat")
  if [ -z "$pids" ]; then idle=$((idle+1)); [ $idle -gt 6 ] && break; sleep 10; continue; fi
  idle=0; tot=0; line="$(date +%s)"
  for p in $pids; do r=$(awk '/VmRSS/{print $2}' /proc/$p/status 2>/dev/null); [ -n "$r" ] && { tot=$((tot+r)); line="$line $p:$((r/1024))"; }; done
  echo "$line total_MiB=$((tot/1024))" >> $log
  sleep 10
done
