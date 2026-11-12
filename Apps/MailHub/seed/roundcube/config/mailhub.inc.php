<?php
// MailHub: Roundcube settings beyond what the image's env vars cover.

$config['product_name'] = 'MailHub';
// Elastic2022 (community skin, light + dark). Ten others are installed and can be
// picked in Settings → User interface: Elastic, Workbench, Elastic2025, Stretched
// Elastic, Outlook, Air, Air Blue, Elastic Google, hellomail, Accessibility.
$config['skin'] = 'elastic2022';

// No login form: mailhub_sso logs the identity AppShield signed into its own
// Dovecot mailbox (a bare user name: admin, then one per identity). A session that
// times out (session_lifetime, 10 idle minutes) is simply opened again.
$config['username_domain'] = '';

// Sent mail is kept in the unified mailbox; providers keep their own copy too.
$config['sent_mbox'] = 'Sent';

// Accounts can deliver into their own folder (Settings → Mail accounts → Folder):
// show unread counts on every folder, not only the Inbox.
$config['check_all_folders'] = true;

// Conversations: the message list groups replies into threads (Dovecot answers
// IMAP THREAD), with the threads holding unread mail opened. Only the default:
// List options → List mode in a folder overrides it for that folder.
$config['default_list_mode'] = 'threads';
$config['autoexpand_threads'] = 2;

// --- Per-identity SMTP (identity_smtp) ----------------------------------------
// Each identity sends through its provider's SMTP. The global smtp_host is only
// the fallback identity_smtp requires to exist.

// --- Calendar & contacts --------------------------------------------------------
// The mailhub_dav plugin loads `calendar` and `kolab_addressbook` against the
// built-in Baïkal (same login as the mailbox), or against another CalDAV/CardDAV
// server the user sets in Settings → Calendar & contacts.
$config['mailhub_dav_default_url'] = 'http://mailhub-dav/dav.php';
$config['calendar_default_view'] = 'agendaWeek';
$config['calendar_itip_send_option'] = 3;      // reply to organizer + allow comment
$config['calendar_itip_after_action'] = 0;     // keep the invitation mail
$config['kolab_cache'] = true;
// kolab_addressbook appends its CardDAV books to this list itself (config_get
// hook); a literal 'kolab' id is not a source and makes autocomplete fail (700).
$config['autocomplete_addressbooks'] = ['sql'];

$config['dav_debug'] = (bool) getenv('MAILHUB_DAV_DEBUG');
