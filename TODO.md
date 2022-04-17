# Tasks
* Some logging level or quiet/non-quiet config to disable, for example, the `-q` flag to `scp`
* Flake dev with all required commands: `cfssl`, `wget`, `kubectl`, ...
* Stop hardcoding filenames such as `kube-scheduler.yaml`? I've set these in variables from functions, but not in th heredoc files
* I've added a step in `bootstrap_etcd` to clean previous leftovers, add a `Step 0` that does this for all servers and any kinds of leftovers

## Not so important
* Decide between uppercase and lowercase variable names already

## Future
* Literally any language would be better than bash
* OpenAPI spec for the config file
* So much calling `jq` gotta be making it slow
* Verifications:
  * Correct files are generated
  * Files are uploaded to the servers?
  * Cluster info is correct?
