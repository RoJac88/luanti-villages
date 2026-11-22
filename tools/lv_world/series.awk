/work start day/ { match($0,/day [0-9]+/); d=substr($0,RSTART+4,RLENGTH-4); match($0,/hunger.*/); h[d]=substr($0,RSTART+7); order[++n]=d; cur=d }
/\] dinner / { match($0,/posted=[0-9]+ factor=[0-9.]+( plate=[0-9.a-z]+)?/); din[cur]=substr($0,RSTART,RLENGTH) }
/\] money total/ && !(cur in mon) { match($0,/total=[0-9]+ top3=[0-9]+%/); mon[cur]=substr($0,RSTART,RLENGTH) }
/\] prices/ && !(cur in fd) { if (match($0,/food=x[0-9.]+/)) fd[cur]=substr($0,RSTART+5,RLENGTH-5); else if (match($0,/dinner=x[0-9.]+/)) fd[cur]="d" substr($0,RSTART+7,RLENGTH-7); if (match($0,/stone=x[0-9.]+/)) st[cur]=substr($0,RSTART+6,RLENGTH-6); if (match($0,/planks=x[0-9.]+/)) pl[cur]=substr($0,RSTART+7,RLENGTH-7); if (match($0,/wheat_item=x[0-9.]+/)) wh[cur]=substr($0,RSTART+11,RLENGTH-11)}
END { for (i=1;i<=n;i++){d=order[i]; if (d==last) continue; last=d; printf "%s | %s | %s | %s | food %s stone %s planks %s wheat %s\n", d, h[d], din[d], mon[d], fd[d], st[d], pl[d], wh[d]} }
