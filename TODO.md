# Tasks
* Literally any language would be better than bash
* OpenAPI spec for the config file
* So much calling `jq` gotta be making it slow
* Separate script for cert generation? Since there's `gen_csr`, I could also have some function that runs `cfssl`
* Default for `gen_csr` that autosets `OU` to `$CERT_OU`?
