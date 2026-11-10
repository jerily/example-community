port 8080
tenant community
site_name {Juniper Yard}
listen_host 127.0.0.1
num_threads 1
home_path /a-little-space-to-grow
origin http://localhost:8080
sqlite_path ./data/community.sqlite3
key_file ./data/community.keyset
account {
    bcrypt_cost 12 password_min_length 15
    totp_digits 6 totp_period 30 totp_algorithm SHA1 totp_window 1
    session_ttl 43200 code_ttl 900 challenge_ttl 600
    throttle_window 900 browse_limit 120 post_limit 60 account_limit 10 challenge_limit 5
    form_max_bytes 32768
}
user {prefix /user title Account issuer {Juniper Yard} deliver {}}
forum {prefix /forum title Discussions page_size 100 body_max_length 10000 title_max_length 160 post_limit 30}
wiki {allow_create true}
blog {allow_create true}
