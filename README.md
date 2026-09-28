# SA ID Search — CloudSmiths Salesforce Developer Assignment

A public Experience Cloud (LWR) page where a visitor enters a South African ID number, the number is
validated (format, real date, citizenship digit, Luhn checksum), the decoded data is stored with a running
search counter, and the public holidays for the visitor's birth year are shown — with their birthday flagged if
it falls on one. Holiday data comes from the Calendarific API via a background sync, never from the guest
request.

## Architecture at a glance

```
Visitor (guest)                                   Admin / scheduled job (internal context)
     │                                                        │
     ▼                                                        ▼
c/idSearch (LWC)  ──►  IdSearchController.search()     HolidaySyncScheduler (1 Jan, annual)
  c/saIdNumber           │  SAIdValidator.parse()             │
  (client-side           │  upsert ID_Search__c (+1 count)    ▼
   validation, UX only)  │  read Public_Holiday__c      HolidaySyncBatch (scope 1 = one year per txn)
                         ▼                                    │  HolidaySyncService.syncYear()
                    SearchResult DTO                          │    CalendarificService.fetchHolidays()
                                                              │    upsert Public_Holiday__c on External_Key__c
                                                              ▼    log to Integration_Log__c
                                                 Named Credential "Calendarific" + Web_Service_Setting__mdt (path template + key)
```

| Concern | Where |
|---|---|
| ID rules (single source of truth) | [SAIdValidator.cls](force-app/main/default/classes/SAIdValidator.cls); client mirror in [saIdNumber.js](force-app/main/default/lwc/saIdNumber/saIdNumber.js) |
| Guest entry point | [IdSearchController.cls](force-app/main/default/classes/IdSearchController.cls) — `without sharing`, CRUD/FLS-guarded, no callout |
| Calendarific client | [CalendarificService.cls](force-app/main/default/classes/CalendarificService.cls) — supplies `{year}`, parses the reply |
| Web service settings | [WebServiceSettings.cls](force-app/main/default/classes/WebServiceSettings.cls) — resolves `Web_Service_Setting__mdt` (Named Credential + templated `Path__c`) into an `HttpRequest` |
| Cache population | [HolidaySyncService.cls](force-app/main/default/classes/HolidaySyncService.cls), [HolidaySyncBatch.cls](force-app/main/default/classes/HolidaySyncBatch.cls), [HolidaySyncScheduler.cls](force-app/main/default/classes/HolidaySyncScheduler.cls) |
| UI | [lwc/idSearch](force-app/main/default/lwc/idSearch/) |
| Data model | `ID_Search__c` (PII, Private), `Public_Holiday__c` (public reference data), `Integration_Log__c` (internal), `Web_Service_Setting__mdt` (per-service Named Credential, templated path, key) |
| Access | `ID_Search_Guest_Access` (site guest user), `SA_ID_Search_Admin` (admins / deploying user) |

## Security model (guest user)

* The guest permission set grants Read + Create on `ID_Search__c` (Create depends on Read at deploy time, and the
  platform refuses to assign Edit/Delete to a guest user at all) and Read on `Public_Holiday__c`. Nothing else.
  The counter increment is therefore a system-mode side effect of a Create-permitted search.
* Record-level visibility of `ID_Search__c` is withheld by the sharing model: OWD Private, external Private,
  **no guest sharing rules**. A guest can never list or read back other visitors' searches through any
  sharing-enforced path (LDS, list views, reports, `with sharing` Apex).
* `IdSearchController` runs `without sharing` on purpose: guests do not own the records they create, so a
  `with sharing` lookup would never find the existing record and the counter could never increment. The only
  `ID_Search__c` query is filtered on exactly the ID number the caller submitted, and a describe-based
  CRUD/FLS guard keeps the permission set the real gate even though Apex bypasses object permissions.
* The guest transaction contains **no callout**. The Calendarific key lives in `Web_Service_Setting__mdt` and is only
  read by the sync classes, which run in an internal context.
* **POPIA note:** `ID_Search__c` stores a national ID number and a derived date of birth. The controls above
  contain exposure; encryption at rest (Shield), a retention/deletion policy and consent capture are outside
  the assignment's scope and should be treated as a consciously accepted risk, not an oversight.

## Setup (per org)

1. Deploy: `sf project deploy start -o <org> --source-dir force-app`
2. Assign the admin permission set to yourself (also required for the Apex tests to have FLS on the new fields):
   `sf org assign permset -n SA_ID_Search_Admin -o <org>`
3. Set the Calendarific key: Setup → Custom Metadata Types → Web Service Setting → **Calendarific Holidays** →
   API Key. Use your own key from a private Calendarific account; never commit it. **Do not redeploy
   `customMetadata/Web_Service_Setting.Calendarific_Holidays.md-meta.xml` afterwards** — its key is blank in
   source and a deploy overwrites the org value (the next sync then logs "has no API Key").
4. Warm the holiday cache (5 years back through next year):
   `sf apex run -o <org> -f scripts/apex/syncHolidays.apex`
   Backfill older birth years by editing `fromYear`/`toYear` in that script, or sync one specific year with
   `scripts/apex/syncSingleYear.apex` (set `yearToSync`) or inline:
   `echo "HolidaySyncService.syncYear(1994);" | sf apex run -o <org>`.
   The year fills the `{year}` placeholder of the record's `Path__c`
   (`/holidays?api_key={apiKey}&country=ZA&year={year}&type=national`); `{apiKey}` is filled from the
   record's API Key. Change country/type/location by editing the path — no code change needed. Outcomes are in
   the **Integration Logs** tab.
5. Register the annual refresh: `sf apex run -o <org> -f scripts/apex/scheduleHolidaySync.apex`
6. Experience site: `sf community create --name "SA ID Search" --template-name "Build Your Own (LWR)" --url-path-prefix idsearch -o <org>`,
   then in Experience Builder drop **SA ID Search** (`c:idSearch`) on the Home page, enable public access
   (Settings → General → *Guest users can see and interact with your site without logging in*), assign
   `ID_Search_Guest_Access` to the site's guest user (Settings → General → Guest User Profile → Permission Set
   Assignments), publish, and activate (Administration → Settings → Activate).

## Tests

* Apex: `sf apex run test -o <org> --tests SAIdValidatorTest --tests CalendarificServiceTest --tests HolidaySyncServiceTest --tests IdSearchControllerTest --tests WebServiceSettingsTest --code-coverage`
* LWC: `npm install && npm test`
* Lint/format: `npm run lint`, `npm run prettier:verify`

The SA ID test vectors are shared between `SAIdValidatorTest.cls` and `saIdNumber.test.js`; change both
together. `TestDataFactory.buildSaIdNumber()` mints valid IDs with a correct Luhn digit for any birth date /
gender / citizenship.

## Known limitations / decisions

* Counter increments on every successful server-side search (double-clicks are prevented client-side by
  disabling the button while a request is in flight; there is no session-level dedup).
* Two simultaneous first searches for the same ID cannot both fail (upsert on the external ID), but two
  simultaneous repeat searches can lose one increment. Accepted for this tool's traffic instead of `FOR UPDATE`.
* A birth year that has not been synced yet shows a "not available yet" state; the search is still recorded.
  There is deliberately no guest-triggered on-demand sync.
* Century inference: a two-digit year is placed in the most recent century that does not put the birth date in
  the future (so `26` → 2026, `27` → 1927).
* Holidays removed upstream are not deleted from the cache by a re-sync (upsert only).
