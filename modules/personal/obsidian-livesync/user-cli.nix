{
    den.aspects.obsidian-livesync.nixos = {
        config,
        pkgs,
        ...
    }: let
        svc = config.my.services.obsidian-livesync;

        cli = pkgs.writeShellApplication {
            name = "obsidian-livesync-user";
            runtimeInputs = [pkgs.coreutils pkgs.curl pkgs.gawk pkgs.jq];
            text = ''
                base="http://127.0.0.1:${toString svc.port}"
                secret=${config.sops.secrets.obsidian.path}

                usage() {
                    cat >&2 <<'USAGE'
                obsidian-livesync-user -- manage CouchDB accounts for Obsidian LiveSync

                  add <user> <database>     create the account, the database and its access rule
                  grant <user> <database>   give an existing account access to another database
                  passwd <user>             change an account's password
                  remove <user>             delete an account (databases are left untouched)
                  reset <database>          erase a database and recreate it empty, keeping its accounts
                  list                      show accounts, databases and who may reach them

                New databases are seeded so the LiveSync plugin treats them as already
                initialised and never asks to destroy them, which it cannot do as a
                non-admin account.

                Reads the CouchDB admin credential, so it must run as root:
                  sudo obsidian-livesync-user list
                USAGE
                }

                if [ ! -r "$secret" ]; then
                    echo "cannot read $secret -- run this with sudo" >&2
                    exit 1
                fi

                creds=$(awk -F'=' '
                    { sub(/\r$/, "") }
                    /^[[:space:]]*[;#]/ { next }
                    /^[[:space:]]*\[/ { section = $1; sub(/^[[:space:]]+/, "", section) }
                    section == "[admins]" && NF > 1 {
                        name = $1; sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+$/, "", name)
                        pass = substr($0, index($0, "=") + 1); sub(/^[[:space:]]+/, "", pass)
                        print name "\t" pass
                        exit
                    }
                ' "$secret")
                if [ -z "$creds" ]; then
                    echo "no [admins] entry found in $secret" >&2
                    exit 1
                fi
                admin_user=$(printf '%s' "$creds" | cut -f1)
                admin_pass=$(printf '%s' "$creds" | cut -f2)
                case $admin_pass in
                    -*)
                        echo "the [admins] password is stored pre-hashed and cannot be used for HTTP auth" >&2
                        exit 1
                        ;;
                esac

                couch() {
                    local method=$1 path=$2
                    shift 2
                    curl -s -u "$admin_user:$admin_pass" -X "$method" \
                        -H 'Content-Type: application/json' "$base$path" "$@"
                }

                die() {
                    echo "$1" >&2
                    exit 1
                }

                check_ok() {
                    [ "$(printf '%s' "$1" | jq -r '.ok // empty')" = "true" ] || die "$2: $1"
                }

                reachable() {
                    [ "$(couch GET /_up | jq -r '.status // empty')" = "ok" ] \
                        || die "couchdb is not answering on $base -- is couchdb.service running?"
                }

                read_new_password() {
                    local user=$1 first second
                    read -rsp "New password for $user: " first; echo >&2
                    read -rsp "Repeat: " second; echo >&2
                    [ -n "$first" ] || die "empty password"
                    [ "$first" = "$second" ] || die "passwords do not match"
                    printf '%s' "$first"
                }

                user_rev() {
                    couch GET "/_users/org.couchdb.user:$1" | jq -r '._rev // empty'
                }

                write_user() {
                    local user=$1 password=$2 rev payload out
                    rev=$(user_rev "$user")
                    payload=$(jq -n --arg n "$user" --arg p "$password" --arg r "$rev" \
                        '{name: $n, password: $p, roles: [], type: "user"}
                         + (if $r == "" then {} else {_rev: $r} end)')
                    out=$(couch PUT "/_users/org.couchdb.user:$user" -d "$payload")
                    check_ok "$out" "could not write account $user"
                }

                ensure_db() {
                    local db=$1 out err
                    out=$(couch PUT "/$db")
                    err=$(printf '%s' "$out" | jq -r '.error // empty')
                    if [ -n "$err" ] && [ "$err" != "file_exists" ]; then
                        die "could not create database $db: $out"
                    fi
                }

                seed_doc() {
                    local db=$1 docid=$2 payload=$3 out
                    [ -n "$(couch GET "/$db/$docid" | jq -r '.error // empty')" ] || return 0
                    out=$(couch PUT "/$db/$docid" -d "$payload")
                    check_ok "$out" "could not seed $docid into $db"
                }

                seed_database() {
                    local db=$1 salt created
                    salt=$(head -c 32 /dev/urandom | base64 -w0)
                    created=$(date +%s%3N)
                    seed_doc "$db" obsydian_livesync_version \
                        '{"version": 12, "type": "versioninfo"}'
                    seed_doc "$db" _local/obsidian_livesync_sync_parameters \
                        "$(jq -n --arg s "$salt" \
                            '{type: "sync-parameters", protocolVersion: 2, pbkdf2salt: $s}')"
                    seed_doc "$db" _local/obsydian_livesync_milestone \
                        "$(jq -n --argjson c "$created" \
                            '{type: "milestoneinfo", created: $c, locked: false, accepted_nodes: [],
                              node_info: {}, node_chunk_info: {}, tweak_values: {}, cleaned: false}')"
                }

                db_members() {
                    couch GET "/$1/_security" | jq -r '(.members.names // []) | join(" ")'
                }

                grant_member() {
                    local db=$1 user=$2 sec payload out
                    sec=$(couch GET "/$db/_security")
                    printf '%s' "$sec" | jq -e 'type == "object"' >/dev/null \
                        || die "could not read access rule for $db: $sec"
                    payload=$(printf '%s' "$sec" | jq --arg n "$user" '
                        (.admins //= {names: [], roles: []})
                        | (.members //= {names: [], roles: []})
                        | .members.names = ((.members.names // []) + [$n] | unique)')
                    out=$(couch PUT "/$db/_security" -d "$payload")
                    check_ok "$out" "could not grant $user access to $db"
                }

                cmd=''${1-}
                case $cmd in
                    add)
                        [ $# -eq 3 ] || { usage; exit 1; }
                        reachable
                        password=$(read_new_password "$2")
                        write_user "$2" "$password"
                        ensure_db "$3"
                        seed_database "$3"
                        grant_member "$3" "$2"
                        echo "account $2 may now sync database $3 at ${svc.url}"
                        ;;
                    grant)
                        [ $# -eq 3 ] || { usage; exit 1; }
                        reachable
                        [ -n "$(user_rev "$2")" ] || die "no such account: $2"
                        ensure_db "$3"
                        seed_database "$3"
                        grant_member "$3" "$2"
                        echo "account $2 may now sync database $3"
                        ;;
                    passwd)
                        [ $# -eq 2 ] || { usage; exit 1; }
                        reachable
                        [ -n "$(user_rev "$2")" ] || die "no such account: $2"
                        password=$(read_new_password "$2")
                        write_user "$2" "$password"
                        echo "password for $2 changed"
                        ;;
                    remove)
                        [ $# -eq 2 ] || { usage; exit 1; }
                        reachable
                        rev=$(user_rev "$2")
                        [ -n "$rev" ] || die "no such account: $2"
                        out=$(couch DELETE "/_users/org.couchdb.user:$2?rev=$rev")
                        check_ok "$out" "could not remove account $2"
                        echo "account $2 removed -- its databases still exist"
                        ;;
                    reset)
                        [ $# -eq 2 ] || { usage; exit 1; }
                        reachable
                        db=$2
                        info=$(couch GET "/$db")
                        [ -z "$(printf '%s' "$info" | jq -r '.error // empty')" ] \
                            || die "no such database: $db"
                        members=$(db_members "$db")
                        echo "database $db holds $(printf '%s' "$info" | jq -r .doc_count) document(s)"
                        echo "accounts that will be restored: ''${members:-none}"
                        echo "every document in it will be erased."
                        read -rp "type the database name to confirm: " confirm
                        [ "$confirm" = "$db" ] || die "aborted"
                        out=$(couch DELETE "/$db")
                        check_ok "$out" "could not delete $db"
                        ensure_db "$db"
                        seed_database "$db"
                        for member in $members; do
                            grant_member "$db" "$member"
                        done
                        echo "$db is empty, seeded and reachable by: ''${members:-none}"
                        ;;
                    list)
                        [ $# -eq 1 ] || { usage; exit 1; }
                        reachable
                        echo "accounts:"
                        couch GET /_users/_all_docs \
                            | jq -r '.rows[].id | select(startswith("org.couchdb.user:"))
                                     | "  " + ltrimstr("org.couchdb.user:")'
                        echo "databases:"
                        for db in $(couch GET /_all_dbs | jq -r '.[] | select(startswith("_") | not)'); do
                            members=$(couch GET "/$db/_security" \
                                | jq -r 'if (.members.names // []) | length > 0
                                         then .members.names | join(", ")
                                         elif (.members.roles // []) | length > 0
                                         then "no accounts -- roles only: " + (.members.roles | join(", "))
                                         else "any valid user"
                                         end')
                            printf '  %s -- %s\n' "$db" "$members"
                        done
                        ;;
                    *)
                        usage
                        exit 1
                        ;;
                esac
            '';
        };
    in {
        environment.systemPackages = [cli];
    };
}
