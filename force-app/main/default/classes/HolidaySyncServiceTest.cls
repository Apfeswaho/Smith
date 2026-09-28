/**
 * @description Covers the sync service, batch and scheduler. Test data goes in before Test.startTest(): Apex
 *              rejects a callout after uncommitted DML, even a mocked one.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
@IsTest
private class HolidaySyncServiceTest {
  private static final Integer YEAR = 2024;

  private static void useTestApiKey() {
    TestDataFactory.useCalendarificSetting('test-api-key');
  }

  private static List<Integration_Log__c> queryLogs() {
    return [
      SELECT Status__c, Year__c, Record_Count__c, Message__c
      FROM Integration_Log__c
      WHERE Process__c = :HolidaySyncService.PROCESS_NAME
    ];
  }

  @IsTest
  static void successfulSyncUpsertsHolidaysAndLogsSuccess() {
    useTestApiKey();
    Test.setMock(
      HttpCalloutMock.class,
      CalendarificCalloutMock.success(YEAR, 5)
    );

    Test.startTest();
    HolidaySyncService.SyncResult result = HolidaySyncService.syncYear(YEAR);
    Test.stopTest();

    List<Public_Holiday__c> holidays = [
      SELECT
        Name,
        Holiday_Name__c,
        Holiday_Date__c,
        Holiday_Type__c,
        Year__c,
        External_Key__c
      FROM Public_Holiday__c
      ORDER BY Holiday_Date__c
    ];
    Assert.isTrue(
      result.isSuccess,
      'Sync should report success, got: ' + result.errorMessage
    );
    Assert.areEqual(
      5,
      result.holidayCount,
      'Result should report the number of holidays upserted'
    );
    Assert.areEqual(
      5,
      holidays.size(),
      'One Public_Holiday__c per holiday in the payload'
    );
    Assert.areEqual(
      'Sample Holiday 0',
      holidays[0].Holiday_Name__c,
      'Holiday name should be stored'
    );
    Assert.areEqual(
      'Sample Holiday 0',
      holidays[0].Name,
      'Record Name should mirror the holiday name'
    );
    Assert.areEqual(
      Date.newInstance(YEAR, 1, 1),
      holidays[0].Holiday_Date__c,
      'Holiday date should be stored'
    );
    Assert.areEqual(
      YEAR,
      holidays[0].Year__c.intValue(),
      'Year should be denormalised from the date'
    );
    Assert.areEqual(
      'ZA-2024-01-01-sample-holiday-0',
      holidays[0].External_Key__c,
      'External key should be country-date-slug'
    );
    Assert.areEqual(
      'National holiday',
      holidays[0].Holiday_Type__c,
      'Primary type should be stored'
    );

    List<Integration_Log__c> logs = queryLogs();
    Assert.areEqual(
      1,
      logs.size(),
      'Every sync run should write one log entry'
    );
    Assert.areEqual(
      HolidaySyncService.STATUS_SUCCESS,
      logs[0].Status__c,
      'Log should record success'
    );
    Assert.areEqual(
      5,
      logs[0].Record_Count__c.intValue(),
      'Log should record how many holidays were upserted'
    );
    Assert.areEqual(
      YEAR,
      logs[0].Year__c.intValue(),
      'Log should record the synced year'
    );
  }

  @IsTest
  static void rerunningSameYearDoesNotCreateDuplicates() {
    List<CalendarificService.Holiday> firstRun = CalendarificService.parseHolidays(
      CalendarificCalloutMock.successBody(YEAR, 3)
    );
    List<Public_Holiday__c> existing = HolidaySyncService.toRecords(firstRun);
    existing[0].Holiday_Type__c = 'Stale type';
    upsert existing External_Key__c;
    useTestApiKey();
    Test.setMock(
      HttpCalloutMock.class,
      CalendarificCalloutMock.success(YEAR, 3)
    );

    Test.startTest();
    HolidaySyncService.SyncResult result = HolidaySyncService.syncYear(YEAR);
    Test.stopTest();

    List<Public_Holiday__c> holidays = [
      SELECT Id, Holiday_Type__c
      FROM Public_Holiday__c
      WHERE Year__c = :YEAR
      ORDER BY Holiday_Date__c
    ];
    Assert.isTrue(
      result.isSuccess,
      'Re-run should succeed, got: ' + result.errorMessage
    );
    Assert.areEqual(
      3,
      holidays.size(),
      'Re-running the sync must update in place, not duplicate'
    );
    Assert.areEqual(
      existing[0].Id,
      holidays[0].Id,
      'The existing record should be matched on External_Key__c'
    );
    Assert.areEqual(
      'National holiday',
      holidays[0].Holiday_Type__c,
      'Re-run should refresh stale field values'
    );
  }

  @IsTest
  static void calloutFailureIsLoggedAndDoesNotThrow() {
    useTestApiKey();
    Test.setMock(
      HttpCalloutMock.class,
      new CalendarificCalloutMock(500, 'Internal Server Error', '')
    );

    Test.startTest();
    HolidaySyncService.SyncResult result = HolidaySyncService.syncYear(YEAR);
    Test.stopTest();

    List<Integration_Log__c> logs = queryLogs();
    Assert.isFalse(
      result.isSuccess,
      'A failed callout should be reported as unsuccessful'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Public_Holiday__c],
      'No holidays should be written when the callout fails'
    );
    Assert.areEqual(
      1,
      logs.size(),
      'A failed run should still write exactly one log entry'
    );
    Assert.areEqual(
      HolidaySyncService.STATUS_FAILED,
      logs[0].Status__c,
      'Log should record the failure'
    );
    Assert.isTrue(
      logs[0].Message__c.contains('500'),
      'Log message should carry the underlying error, got: ' +
      logs[0].Message__c
    );
    Assert.isTrue(
      logs[0].Message__c.contains('CalendarificException'),
      'Log message should name the exception type, got: ' + logs[0].Message__c
    );
  }

  @IsTest
  static void missingApiKeyIsLoggedAsFailure() {
    TestDataFactory.useCalendarificSetting(null);

    Test.startTest();
    HolidaySyncService.SyncResult result = HolidaySyncService.syncYear(YEAR);
    Test.stopTest();

    Assert.isFalse(
      result.isSuccess,
      'A missing key should be reported as unsuccessful'
    );
    Assert.isTrue(
      result.errorMessage.contains('WebServiceSettings.SettingException') &&
      result.errorMessage.contains('API Key'),
      'Result should explain the key is missing, got: ' + result.errorMessage
    );
    Assert.areEqual(
      HolidaySyncService.STATUS_FAILED,
      queryLogs()[0].Status__c,
      'Log should record the failure'
    );
  }

  @IsTest
  static void externalKeySlugifiesNameAndIncludesDate() {
    CalendarificService.Holiday holiday = new CalendarificService.Holiday();
    holiday.name = 'Workers\' Day (observed)';
    holiday.holidayDate = Date.newInstance(2024, 5, 1);

    Assert.areEqual(
      'ZA-2024-05-01-workers-day-observed',
      HolidaySyncService.buildExternalKey(holiday),
      'Key should be country-date-slug with punctuation collapsed to hyphens'
    );
  }

  @IsTest
  static void batchSyncsEachYearInScopeAndLogsOutcome() {
    useTestApiKey();
    Test.setMock(
      HttpCalloutMock.class,
      CalendarificCalloutMock.success(YEAR, 4)
    );

    Test.startTest();
    Id jobId = HolidaySyncBatch.runRange(YEAR, YEAR);
    Test.stopTest();

    Assert.isNotNull(jobId, 'runRange should enqueue a batch job');
    Assert.areEqual(
      4,
      [SELECT COUNT() FROM Public_Holiday__c WHERE Year__c = :YEAR],
      'The batch should sync the requested year'
    );
    Assert.areEqual(
      HolidaySyncService.STATUS_SUCCESS,
      queryLogs()[0].Status__c,
      'The batch run should be logged'
    );
  }

  @IsTest
  static void batchStartYieldsEveryRequestedYear() {
    List<Integer> years = new List<Integer>();
    for (
      Integer year : new HolidaySyncBatch(new List<Integer>{ 2022, 2023, 2024 })
        .start(null)
    ) {
      years.add(year);
    }

    Assert.areEqual(
      new List<Integer>{ 2022, 2023, 2024 },
      years,
      'start() should iterate exactly the years passed in'
    );
    Assert.areEqual(
      1,
      HolidaySyncBatch.SCOPE_SIZE,
      'Scope must stay at 1: each year is callout-then-DML and needs its own transaction'
    );
  }

  // No startTest/stopTest: stopTest would run the two-year batch, and a test allows only one batch scope.
  @IsTest
  static void schedulerRegistersAnnualCronJob() {
    Id cronId = HolidaySyncScheduler.scheduleAnnual();

    CronTrigger cron = [
      SELECT CronExpression, CronJobDetail.Name
      FROM CronTrigger
      WHERE Id = :cronId
    ];
    Assert.areEqual(
      HolidaySyncScheduler.CRON_ANNUAL,
      cron.CronExpression,
      'Job should run on the annual cron expression'
    );
    Assert.areEqual(
      HolidaySyncScheduler.JOB_NAME,
      cron.CronJobDetail.Name,
      'Job should be registered under its documented name'
    );
  }

  @IsTest
  static void yearsToSyncDefaultsToCurrentAndNextYear() {
    Integer currentYear = Date.today().year();

    Assert.areEqual(
      new List<Integer>{ currentYear, currentYear + 1 },
      HolidaySyncScheduler.yearsToSync(),
      'The annual run should refresh the current year and pre-warm the next'
    );
  }

  @IsTest
  static void schedulerExecutionRunsBatchForYearsToSync() {
    useTestApiKey();
    HolidaySyncScheduler.yearsToSyncOverride = new List<Integer>{ YEAR };
    Test.setMock(
      HttpCalloutMock.class,
      CalendarificCalloutMock.success(YEAR, 2)
    );

    Test.startTest();
    new HolidaySyncScheduler().execute(null);
    Test.stopTest();

    Assert.areEqual(
      2,
      [SELECT COUNT() FROM Public_Holiday__c WHERE Year__c = :YEAR],
      'Executing the scheduled job should run HolidaySyncBatch for the years to sync'
    );
    Assert.areEqual(
      HolidaySyncService.STATUS_SUCCESS,
      queryLogs()[0].Status__c,
      'The scheduled run should be logged'
    );
  }
}
