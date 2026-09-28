// Sync ONE specific year from Calendarific into Public_Holiday__c (synchronous, one callout).
// Set the year below, then:  sf apex run -o <org> -f scripts/apex/syncSingleYear.apex
// Or inline without editing:  echo "HolidaySyncService.syncYear(1994);" | sf apex run -o <org>
// The year becomes the &year= query parameter of GET /api/v2/holidays (see CalendarificService.buildEndpoint).
Integer yearToSync = 1994;

HolidaySyncService.SyncResult result = HolidaySyncService.syncYear(yearToSync);
System.debug(
  'Year ' +
    result.year +
    ' success=' +
    result.isSuccess +
    ' holidays=' +
    result.holidayCount +
    ' error=' +
    result.errorMessage
);
