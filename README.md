# nreplicas
Automate a way to create N cascading Replicas of a Master

# Issues
It is possible that 'ulimit -Hn' is set too low, for e.g. 5000, in which case after ~5000/9 replicas the script would bail out (with Resource unavailable etc. error. Confirm this issue with 'ps -eLf | wc -l' being just below the ulimit
