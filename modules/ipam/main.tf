###############################################################
# Module: ipam
# Passes through the existing IPAM pool ID.
# The data source lookup was removed — it caused 20+ minute
# hangs due to AWS IPAM API throttling/timeouts.
# The pool ID is already known and passed in via var.ipam_pool_id.
###############################################################
