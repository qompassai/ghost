-- Prosody Example Configuration File
--
-- Information on configuring Prosody can be found on our
-- website at https://prosody.im/doc/configure
--
-- Tip: You can check that the syntax of this file is correct
-- when you have finished by running this command:
--     prosodyctl check config
-- If there are any errors, it will let you know what and where
-- they are, otherwise it will keep quiet.
--
-- The only thing left to do is rename this file to remove the .dist ending, and fill in the
-- blanks. Good luck, and happy Jabbering!


---------- Server-wide settings ----------
-- Settings in this section apply to the whole server and are the default settings
-- for any virtual hosts

-- This is a (by default, empty) list of accounts that are admins
-- for the server. Note that you must create the accounts separately
-- (see https://prosody.im/doc/creating_accounts for info)
-- Example: admins = { "user1@example.com", "user2@example.net" }
admins = { "map@qompass.ai" }

-- Enable use of libevent for better performance under high load
-- For more information see: https://prosody.im/doc/libevent
use_libevent = true

-- Prosody will always look in its source directory for modules, but
-- this option allows you to specify additional locations where Prosody
-- will look for modules first. For community modules, see https://modules.prosody.im/
-- For a local administrator it's common to place local modifications
-- under /usr/local/ hierarchy:
--plugin_paths = { "/usr/local/lib/prosody/modules" }

-- This is the list of modules Prosody will load on startup.
-- It looks for mod_modulename.lua in the plugins folder, so make sure that exists too.
-- Documentation for bundled modules can be found at: https://prosody.im/doc/modules
modules_enabled = {

	-- Generally required
		"roster"; -- Allow users to have a roster. Recommended ;)
		"saslauth"; -- Authentication for clients and servers. Recommended if you want to log in.
		"tls"; -- Add support for secure TLS on c2s/s2s connections
		"dialback"; -- s2s dialback support
		"disco"; -- Service discovery

	-- Not essential, but recommended
		"carbons"; -- Keep multiple clients in sync
		"pep"; -- Enables users to publish their avatar, mood, activity, playing music and more
		"private"; -- Private XML storage (for room bookmarks, etc.)
		"blocklist"; -- Allow users to block communications with other users
		"vcard4"; -- User profiles (stored in PEP)
		"vcard_legacy"; -- Conversion between legacy vCard and PEP Avatar, vcard

	-- Nice to have
		-- "version"; -- Replies to server version requests
		-- "uptime"; -- Report how long server has been running
		"time"; -- Let others know the time here on this server
		"ping"; -- Replies to XMPP pings with pongs
		-- "register"; -- Allow users to register on this server using a client and change passwords
		"mam"; -- Store messages in an archive and allow users to access it
		"csi_simple"; -- Simple Mobile optimizations

	-- Admin interfaces
		"admin_adhoc"; -- Allows administration via an XMPP client that supports ad-hoc commands
		--"admin_telnet"; -- Opens telnet console interface on localhost port 5582

	-- HTTP modules
		"bosh"; -- Enable BOSH clients, aka "Jabber over HTTP"
		"websocket"; -- XMPP over WebSockets
		"http_files"; -- Serve static files from a directory over HTTP

	-- Other specific functionality
		"posix"; -- POSIX functionality, sends server to background, enables syslog, etc.
		--"limits"; -- Enable bandwidth limiting for XMPP connections
		"groups"; -- Shared roster support
		"server_contact_info"; -- Publish contact information for this service
		--"announce"; -- Send announcement to all online users
		"s2s_bidi"; -- Bi-directional server-to-server (XEP-0288)
		--"welcome"; -- Welcome users who register accounts
		--"watchregistrations"; -- Alert admins of registrations
		--"motd"; -- Send a message to users when they log in
		--"legacyauth"; -- Legacy authentication. Only used by some old clients and bots.
		-- "proxy65"; -- Enables a file transfer proxy service which clients behind NAT can use

	-- Custom added
		"blocking"; -- Allow blocking users
		"alias"; -- Alias onion to clearnet
		"smacks"; -- Stream management
		-- "csi"; -- Client state indication
		"filter_chatstates"; -- Hide typing indication on mobile phones
		"throttle_presence"; -- Update precense on moblile phones less often
		"cloud_notify"; -- Push notifications for mobile
		"conversejs";
		"http_altconnect";
		"external_services";
}

-- These modules are auto-loaded, but should you want
-- to disable them then uncomment them here:
modules_disabled = {
	-- "offline"; -- Store offline messages
	-- "c2s"; -- Handle client connections
	-- "s2s"; -- Handle server-to-server connections
}

-- Disable account creation by default, for security
-- For more information see https://prosody.im/doc/creating_accounts
allow_registration = false

-- Debian:
--   Do not send the server to background, either systemd or start-stop-daemon take care of that.
--
daemonize = false;

-- Debian:
--   Please, don't change this option since /run/prosody/
--   is one of the few directories Prosody is allowed to write to
--
pidfile = "/run/prosody/prosody.pid";

-- Force clients to use encrypted connections? This option will
-- prevent clients from authenticating unless they are using encryption.
ssl = {
	key = "/etc/ssl/private/ssl-cert-snakeoil.key";
	certificate = "/etc/ssl/certs/ssl-cert-snakeoil.pem";
	dhparam = "/etc/prosody/dh4096.pem";
	curve = "X448:X25519:secp521r1:secp384r1:secp256k1";
	ciphers = "HIGH+kEDH:HIGH+kEECDH:HIGH:!RSA:!PSK:!SRP:!3DES:!aNULL:!SHA:!MD5:!CAMELLIA:!ECDHE-RSA-AES256-SHA384:!ECDHE-RSA-AES128-SHA256:!DHE-RSA-AES128-SHA256:!DHE-RSA-AES256-SHA256";
}

c2s_require_encryption = true

-- Force servers to use encrypted connections? This option will
-- prevent servers from authenticating unless they are using encryption.

s2s_require_encryption = true

-- Force certificate authentication for server-to-server connections?

s2s_secure_auth = false

-- Some servers have invalid or self-signed certificates. You can list
-- remote domains here that will not be required to authenticate using
-- certificates. They will be authenticated using DNS instead, even
-- when s2s_secure_auth is enabled.

--s2s_insecure_domains = { "insecure.example" }

-- Even if you disable s2s_secure_auth, you can still require valid
-- certificates for some domains by specifying a list here.

--s2s_secure_domains = { "jabber.org" }

-- Select the authentication backend to use. The 'internal' providers
-- use Prosody's configured data storage to store the authentication data.

authentication = "imap"

-- Select the storage backend to use. By default Prosody uses flat files
-- in its configured data directory, but it also supports more backends
-- through modules. An "sql" backend is included by default, but requires
-- additional dependencies. See https://prosody.im/doc/storage for more info.

storage = "sql" -- Default is "internal" (Debian: "sql" requires one of the
-- lua-dbi-sqlite3, lua-dbi-mysql or lua-dbi-postgresql packages to work)

-- For the "sql" backend, you can uncomment *one* of the below to configure:
--sql = { driver = "SQLite3", database = "prosody.sqlite" } -- Default. 'database' is the filename.
--sql = { driver = "MySQL", database = "prosody", username = "prosody", password = "secret", host = "localhost" }
--sql = { driver = "PostgreSQL", database = "prosody", username = "prosody", password = "secret", host = "localhost" }
sql = { driver = "MySQL", database = "prosody", username = "prosody", password = "YOUR_PASSWORD", host = "localhost" }


-- Archiving configuration
-- If mod_mam is enabled, Prosody will store a copy of every message. This
-- is used to synchronize conversations between multiple clients, even if
-- they are offline. This setting controls how long Prosody will keep
-- messages in the archive before removing them.

archive_expires_after = "1w" -- Remove archived messages after 1 week

-- You can also configure messages to be stored in-memory only. For more
-- archiving options, see https://prosody.im/doc/modules/mod_mam

-- Logging configuration
-- For advanced logging see https://prosody.im/doc/logging
--
-- Debian:
--  Logs info and higher to /var/log
--  Logs errors to syslog also
log = {
	-- Log files (change 'info' to 'debug' for debug logs):
	info = "/var/log/prosody/prosody.log";
	error = "/var/log/prosody/prosody.err";
	-- Syslog:
	{ levels = { "error" }; to = "syslog";  };
}

-- Uncomment to enable statistics
-- For more info see https://prosody.im/doc/statistics
-- statistics = "internal"

-- Certificates
-- Every virtual host and component needs a certificate so that clients and
-- servers can securely verify its identity. Prosody will automatically load
-- certificates/keys from the directory specified here.
-- For more information, including how to use 'prosodyctl' to auto-import certificates
-- (from e.g. Let's Encrypt) see https://prosody.im/doc/certificates

-- Location of directory to find certificates in (relative to main config file):
certificates = "certs"

-- HTTPS currently only supports a single certificate, specify it here:
--https_certificate = "/etc/prosody/certs/localhost.crt"

----------- Virtual hosts -----------
-- You need to add a VirtualHost entry for each domain you wish Prosody to serve.
-- Settings under each VirtualHost entry apply *only* to that host.
-- It's customary to maintain VirtualHost entries in separate config files
-- under /etc/prosody/conf.d/ directory. Examples of such config files can
-- be found in /etc/prosody/conf.avail/ directory.

------ Additional config files ------
-- For organizational purposes you may prefer to add VirtualHost and
-- Component definitions in their own config files. This line includes
-- all config files in /etc/prosody/conf.d/

-- custom
plugin_paths = {"/srv/prosody-modules/"}
compression_level = 9
auth_imap_verify_certificate = false
imap_auth_host = "127.0.0.1"
aliases = {
	["qompass.me"] = "qompass.ai";
	["mapas3rtn54uwmofdo3x2bsdifr47huasnmbgqzfrec5ubupvtpid.onion"] = "qompass.ai";
}
alias_response = "User $alias can be contacted at $target";
default_storage = "sql"
interfaces = { "0.0.0.0", "::" }
contact_info = {
  abuse = { "https://qompass.ai/contact.php", "mailto:map@qompass.ai" };
  admin = { "https://qompass.ai/contact.php", "mailto:map@qompass.ai" };
  feedback = { "https://qompass.ai/contact.php", "mailto:map@qompass.ai" };
  security = { "https://qompass.ai/contact.php", "mailto:map@qompass.ai" };
  support = { "https://qompass.ai/contact.php", "mailto:map@qompass.ai" };
}
data_path = "/var/lib/prosody"
legacy_ssl_ports = {5223}
external_services = {
    {
        type = "stun",
        transport = "udp",
        host = "qompass.ai",
        port = 3478
    }, {
        type = "turn",
        transport = "udp",
        host = "qompass.ai",
        port = 3478,
        secret = "YOUR_SECRET"
    },
    {
        type = "stun",
        transport = "tcp",
        host = "qompass.ai",
        port = 3478
    }, {
        type = "turn",
        transport = "tcp",
        host = "qompass.ai",
        port = 3478,
        secret = "YOUR_SECRET"
    },
    {
        type = "stuns",
        transport = "tcp",
        host = "qompass.ai",
        port = 5349
    }, {
        type = "turns",
        transport = "tcp",
        host = "qompass.ai",
        port = 5349,
        secret = "YOUR_SECRET"
    }
}
conversejs_resources = "/srv/conversejs/dist";
conversejs_options = {
    view_mode = "fullscreen";
    allow_non_roster_messaging = true;
    clear_cache_on_logout = true;
    default_domain = "qompass.ai";
    enable_smacks = true;
    muc_domain = "conference.qompass.ai";
}

VirtualHost "qompass.ai"

--VirtualHost "example.com"
--	certificate = "/path/to/example.crt"


Component "conference.qompass.ai" "muc"
modules_enabled = {
  "vcard_muc",
  "muc_mam" ,
}

Component "proxy.qompass.ai" "proxy65"

Component "upload.qompass.ai" "http_file_share"
http_file_share_size_limit = 100*1024*1024
http_file_share_daily_quota = 100*1024*1024
http_file_share_global_quota = 10*1024*1024*1024

-- see: https://prosody.im/doc/components#adding_an_external_component
--
--Component "gateway.example.com"
--	component_secret = "password"
Include "conf.d/*.cfg.lua"
