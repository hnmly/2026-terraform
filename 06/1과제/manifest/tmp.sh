#!/bin/bash
kubectl delete pod -n unicorn -l component=fluentd --force --grace-period=0
sleep 30
ALB_DNS=$(aws elbv2 describe-load-balancers --names unicorn-alb --query "LoadBalancers[0].DNSName" --output text)
curl -s -X POST "http://$ALB_DNS/v1/book" -H 'Content-Type: application/json' -d '{"client_id":"LOG4","username":"L4","email":"l4@t.com","concert_name":"LT4"}'
echo ""
sleep 10
echo "=== CW Logs ==="
aws logs filter-log-events --log-group-name /unicorn/eks/book-app --limit 3 --query "events[].message" --output text 2>&1
