next_day=`date --date="1 days ago" +%Y-%m-%d`
next_day="$next_day 23:59"

prev_day=`cat /home/ospo/github-mirror/lastrun`

echo -f: $prev_day
echo -t: $next_day

sh /home/ospo/github-mirror/dumps/ght-periodic-dump -f "$prev_day" -t "$next_day"
