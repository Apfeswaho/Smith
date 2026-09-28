// Backfill / refresh the Public_Holiday__c cache from Calendarific for a range of years.
// Run as an admin (never from the guest site):
//   sf apex run -o <org> -f scripts/apex/syncHolidays.apex
// Prerequisite: Web_Service_Setting__mdt record "Calendarific_Holidays" has a real API key.
// Each year runs in its own batch execution (scope 1) and writes an Integration_Log__c row.
Integer fromYear = Date.today().year() - 5;
Integer toYear = Date.today().year() + 1;
Id jobId = HolidaySyncBatch.runRange(fromYear, toYear);
System.debug(
  'HolidaySyncBatch enqueued for ' + fromYear + '-' + toYear + ', job ' + jobId
);
