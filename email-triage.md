# Inbox triage: ten accounts, no filters, 55% noise (2026-09-20 → 09-21)

I had been dreading my own email for months. Ten accounts in Thunderbird — eight
Migadu mailboxes across the estate domains plus two personal Gmail accounts —
and every one of them a wall of static I scrolled past looking for the three
messages that mattered.

This is the record of measuring that properly, discovering the cause was
embarrassingly simple, and fixing it in the one place that actually works.

The tooling lives in `~/Development/inbox-triage/`.

## The cause: no filters. Not one.

Before changing anything I went looking for what was already configured. Every
account's rule file existed and every one contained only its two-line header:

```
version="9"
logging="no"
```

Ten accounts, years of mail, zero filters. Everything had been landing in ten
undifferentiated inboxes since the day each account was created. That is the
whole explanation, and it meant there was no existing setup to understand or
preserve — just an empty space to design into.

## Measuring before touching

I wanted numbers rather than a feeling, so I wrote a scanner that streams the
offline mbox files in
`~/Library/Thunderbird/Profiles/<profile>/ImapMail/*/INBOX`, reads only headers
and skips body bytes. ~2.3 GB in about two seconds.

**11,170 live inbox messages. 55% machine-generated:**

| | count | share |
|---|---:|---:|
| Bulk — carries `List-Unsubscribe` or `List-ID` | 4,152 | 37% |
| Robot — no-reply, auto-submitted, bounces | 2,036 | 18% |
| Actual human correspondence | 4,982 | 45% |

Worst offenders were 88% and 84% noise. Inflow was ~7.8 machine messages a day
from 321 distinct senders.

### Three measurement traps

Getting those numbers right took three corrections, and each one would have
quietly produced a wrong answer.

**1. Read state cannot come from the mbox.** Thunderbird writes a *constant*
`X-Mozilla-Status: 0001` into IMAP offline copies. Every message looks read.
I only noticed because my first run reported zero unread across all ten
accounts, which was obviously false. Real read state lives in the `.msf`, or in
the global search index at `global-messages-db.sqlite` under
`jsonAttributes` key `"59"`. Starred is key `"58"`.

**2. The mbox files hold far more than the folders do.** Raw scan: 24,036
records for 11,270 live messages. Mail moved to Archive or Trash leaves its
bytes behind until compaction, so the mbox is a superset of *everything that
ever passed through*. Deduplicating on `Message-ID` was not enough either —
that only caught the accounts duplicated by the SiteGround → Migadu migration.
The fix was to join against the search index, which tracks live messages only.

**3. Substring matching on addresses is a trap.** My spam classifier flagged 18
messages. Reviewing them, almost all were my own false positives:
`Spe-cialis-t` matched a pharmacy pattern, "cryptography" matched crypto.
Word-anchoring the patterns took it from 18 to **2**.

That is the real finding on spam: **of 11,170 messages, exactly two were
spam.** Migadu and Gmail are catching it upstream, which is precisely why every
`Junk`/`Spam` folder was empty. What was drowning me was *legitimate* bulk mail
I had consented to at some point. Nothing a spam filter will ever help with.

## The decision that mattered: server-side, not client-side

I built the Thunderbird filters first. Then I asked the question I should have
asked at the start — will this work on my phone?

No. **Thunderbird message filters are client-side.** They run only while
Thunderbird is open and fetching. I read mail on iOS too, so mail arriving
overnight would sit unsorted on the phone and then shuffle itself later. The
same message appears in different places depending on which client you look at,
which is worse than no filtering at all.

So I threw that away and checked what the server could do:

```
$ python3 -c "socket + read banner, imap.migadu.com:4190"
"IMPLEMENTATION" "Sora ManageSieve Proxy"
"SIEVE" "fileinto envelope ... imap4flags variables relational vacation
         copy regex date index mailbox subaddress body editheader"
```

**Migadu runs ManageSieve on port 4190.** That changes everything — Sieve runs
at delivery, on the server, so it applies to every client whether or not any of
them is running. Folders are server-side too (they are just IMAP folders), so
they show up everywhere once created.

The final split:

| | where it runs | applies to |
|---|---|---|
| Folders | server (IMAP) | every client |
| Migadu filtering | server (Sieve, port 4190) | every client |
| Gmail filtering | server (Gmail filters) | every client |
| Compaction | local Thunderbird only | local disk |

I deleted the Thunderbird filter generator rather than leave it lying around to
confuse a future me.

## The rule that took three attempts

The first design was the obvious one: anything carrying `List-Unsubscribe` goes
to a `Bulk` folder. It would have been a disaster.

**Google Business Profile sends customer messages with an unsubscribe header.**
176 of them in one mailbox — actual enquiries from actual customers, plus review
notifications, all indistinguishable from marketing by that test. A naive
catch-all buries 176 customer contacts.

Then a subtler one. I had added `mitsui` to a protect list for the bank, and it
matched `<name>-mitsui@<vendor-domain>` — a real person at a supplier, whose
surname happens to contain the bank's name, mid-thread about a ticket machine.
Same bug class as `Spe-cialis-t`. All domain matching is now anchored with
`address :domain :is`, never a substring.

Those two near-misses produced the principle the whole rule set is now built
on:

> **Mail that looks human never moves.**

Every routing decision sits behind an automation test — `List-Unsubscribe`,
`List-ID`, RFC 3834 `Auto-Submitted`, `Precedence: bulk`, or a no-reply style
address. A real person writing from `stripe.com` or `booking.com` stays in the
inbox. "Protected" status exists only to rescue *automated* operational mail
from the Bulk folder, never to redirect human mail.

Second principle, learned the same way: **customer contact is never filed
away.** Contact-form subjects short-circuit every other rule, because those
need a reply. That list needed Japanese (`お客様からのご連絡`, `店の問い合わせ`)
and Swedish (`Kontaktförfrågan`, `Förfrågan`) as well as English — one form per
site, each in its own language.

### Enumerating site names is a losing game

WordPress prefixes admin mail with `[Site Title]`. I built my subject list from
what I could see in the corpus, which was dominated by two busy sites — so
`[Omi House]` and `[@DriveJapanChill]` were never in it, and their mail would
have sat in the inbox forever. `[Wordfence Alert]` as an exact substring also
misses the real subject `[Wordfence Alert - Email Limit Reached]`.

The fix was to stop enumerating and generalise: any bracket-prefixed subject
from one of my own domains is site automation.

```sieve
if anyof (
    header :contains "subject" ["[Wordfence Alert", "Wordfence activity", ...],
    address :all :matches "from" ["wordpress@*", "iot@<my-domain>", ...],
    allof (
        address :domain :is "from" ["nekocafetime.com", "miguelbarroso.com", ...],
        header :matches "subject" "[*"
    )
) {
    fileinto :create "Notifications";
    stop;
}
```

Safe because the contact rule is matched first, and because `Notifications` is a
folder, not a bin. Own-domain mail left stranded in inboxes went from 132 to 35,
and all 35 are contact enquiries and orders that belong there.

## Two accounts deliberately left alone

One mailbox belongs to a client. It is excluded *in code* — the generators emit
nothing for it and the apply script exits if you name it, rather than relying on
me remembering.

The WooCommerce store mailbox is a living order record, so it gets a reduced
script that moves **4 messages** — unambiguous marketing only. All 691 payout
and invoice notifications stay exactly where they are, which works out neatly
because they carry no unsubscribe header, so no catch-all can reach them
anyway.

Late in the day I moved a third mailbox out of scope after it had already been
configured. That exposed a design hole: the exclusion guard blocked the very
command needed to undo the configuration. `EXCLUDE` forbids *configuring*; the
deactivate path is now allowed to name an excluded account, because reverting
moves it back toward untouched. Bulk deactivate still skips them, so it can't
happen by accident.

## Landmines

**Sieve `:regex` is POSIX ERE.** The Perl inline flag `(?i)` is a syntax error,
not a case-insensitivity hint. I dropped the regex dependency entirely and used
glob `:matches`, which is core Sieve and already case-insensitive via
`i;ascii-casemap`.

**Gmail filters have no "stop".** Every matching filter applies. Exclusions have
to be carved out *inside* each filter with `doesNotHaveTheWord` rather than by
ordering rules. Gmail's own `category:promotions|social|updates` classifier does
the heavy lifting, so no sender list is needed there.

**Thunderbird 153 renamed the compaction pref.** It is
`mail.purge_threshold_mb` now — one `h`. The historically misspelled
`threshhold` is inert, so older advice silently does nothing. Default is a
500 MB threshold *with* prompting, which is why nothing had ever compacted.
Set to 20 MB with `mail.purge.ask=false` and it reclaimed **1.0 GB** on next
start (4.9 GB → 3.9 GB), most of it duplicate copies left behind by the estate
migration.

A related curiosity: `mail.prompt_purge_threshold` vanished from `prefs.js`
afterwards. Benign — I had set it to `true`, which is the default, and
`prefs.js` only stores non-defaults.

**`imaplib` has no `.examine()`.** The read-only mailbox open is
`select(mailbox, readonly=True)`, which imaplib maps to `EXAMINE` on the wire.
I wrote `.examine()` from memory and it threw `AttributeError` on the first real
run.

**Always request `UID` explicitly in a FETCH.** Without it, the leading number
in the reply is the *sequence* number. My subject lookup table was keyed by
sequence number while the move list held UIDs, so every lookup missed and a
protection I had written was silently a no-op. Nothing errored. It just quietly
did nothing.

**Migadu's IMAP proxy stops responding above roughly 400 messages per FETCH.**
The client sits in `sock.recv` forever. Measured: a 400-UID request hung, a
334-UID range succeeded, a 706-UID range hung. My first diagnosis blamed the
comma-separated UID list and was wrong — the trigger is *response volume*, not
the shape of the request. Every fetch is now chunked at 150.

**`timeout=` on the `IMAP4_SSL` constructor did not prevent that hang.** It has
to be set on the live socket after login, `m.sock.settimeout(60)`. And `LOGOUT`
itself blocks on a wedged connection, which produced a *second* traceback on
Ctrl-C — cap it to 5 s and drop the socket regardless.

## Archiving without losing anything

The backlog needed clearing, and I did not want deliberate keeps swept up. The
selection is done by the server, so a flagged message is never even a
candidate:

```
BEFORE <date>   UNFLAGGED   SEEN
```

`UNFLAGGED` protects stars. `SEEN` means nothing unread is ever touched —
though as it turned out, **nothing older than 12 months was unread anyway**,
which is the statistic that made the whole exercise feel safe.

Contact-form mail is then held back locally by subject. And when the chunked
fetch can fail, absence from the subject map has to mean *hold back*, not
*archive* — a partial failure must never archive something uninspected. Tested
that path with a deliberately failing mock before trusting it.

**Result: 864 messages archived, 21 held back as customer contact, zero
failures.** Archive is a move, not a delete, so it all stays searchable.

## DMARC, and the DNS that made it moot

I wanted DMARC aggregate reports filed one folder per *domain* rather than per
mailbox, which Sieve does neatly by reading the domain out of the subject
(`Report domain: X`, RFC 7489 §7.2) rather than trusting where it was
delivered.

Then I actually read the DNS:

| domain | record | reports go to |
|---|---|---|
| nekocafetime.com | `p=reject` | `admin@` → **alias → `info@`** |
| ebihara-solutions.com | `p=reject` | `admin@<domain>` |
| miguelbarroso.com | `p=quarantine` | **no `rua=` — no reports at all** |
| omi-house.se | `p=quarantine` | **no `rua=` — no reports at all** |
| drivejapanchill.com | `p=quarantine` | **no `rua=` — no reports at all** |

Three domains have a policy but never asked for reports. So the rule is correct
and almost entirely idle. Proof that `admin@` is an alias rather than a mailbox
came from the one report in the corpus: `Envelope-to: admin@<domain>`,
delivered into `info@`'s inbox.

Consolidating all `rua=` onto one address is the obvious fix, and there is a
step that is easy to miss and silently breaks everything: when `rua=` points
outside the domain being reported on, the *receiving* domain must publish
consent (RFC 7489 §7.1), or most reporters simply refuse to send.

```
nekocafetime.com._report._dmarc.miguelbarroso.com   TXT   "v=DMARC1"
```

One per external domain. Deferred for now.

## Where the Spam/Junk confusion came from

I had both a `Spam` and a `Junk` folder and could never remember which was
which. Three unrelated causes, none of them my fault:

1. **Provider convention.** Migadu calls it `Junk`, Gmail calls it
   `[Gmail]/Spam`. You only ever see one per account.
2. **Thunderbird duplicate mappings** — `Sent`/`Sent-1`, `Archive`/`Archives`,
   `Drafts`/`Drafts-1`. Local artifacts of the estate migration, where two
   local folders claimed one online name. **The `-1` copy is usually the live
   one**: on one account `Sent-1` holds 900 messages and `Sent` holds 0.
   Deleting the wrong one destroys sent mail, so I listed these rather than
   automating them.
3. **Phantom `INBOX/` subfolders** — `INBOX/Junk`, `INBOX/Archives`. Namespace
   probing artifacts, all empty.

## Verifying rather than assuming

Two things I would build again first rather than last.

`--dry-run` initially proved only that my passwords worked. The Sieve syntax was
still unverified, because the server only validates on upload — so a syntax
error would have surfaced *after* activating on some accounts and failing on
others. Migadu supports `CHECKSCRIPT`, which validates server-side without
storing. Now a dry run means something.

And after editing the rules I could not tell whether what was live matched what
was local. `LISTSCRIPTS` + `GETSCRIPT` answers that in seconds, and told me all
six live scripts were 173 bytes short — the Swedish contact patterns I had added
later. Without that check I would have assumed the fixes were live.

## Result

- Inboxes: ~11,200 messages, 55% machine-generated, **zero filters**
- Now: filtered at the provider, so it works in Thunderbird, iOS Mail and
  webmail alike
- 864 messages archived, nothing flagged or unread touched
- 1.0 GB of disk reclaimed
- Two of 11,170 messages turned out to be actual spam

Deferred: the unsubscribe list — 114 senders that still mail me and carry a
working one-click unsubscribe, ranked by volume against how little I open them.
Filters sort noise; unsubscribing stops it. Choosing which of 114 subscriptions
I am genuinely done with turned out to be a harder decision than any of the
engineering, so it can wait.
