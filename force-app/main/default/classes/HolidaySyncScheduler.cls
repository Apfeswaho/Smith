/**
 * @description Annual job: syncs the current and next year, so each year is cached before it's needed.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
public with sharing class HolidaySyncScheduler implements Schedulable {
  public static final String JOB_NAME = 'Calendarific Holiday Sync (annual)';
  // 02:00 on 1 January every year
  public static final String CRON_ANNUAL = '0 0 2 1 1 ? *';

  // Tests can run only one batch scope, so they narrow this to one year.
  @TestVisible
  private static List<Integer> yearsToSyncOverride;

  public static Id scheduleAnnual() {
    return System.schedule(JOB_NAME, CRON_ANNUAL, new HolidaySyncScheduler());
  }

  public static List<Integer> yearsToSync() {
    if (yearsToSyncOverride != null) {
      return yearsToSyncOverride;
    }
    Integer currentYear = Date.today().year();
    return new List<Integer>{ currentYear, currentYear + 1 };
  }

  public void execute(SchedulableContext context) {
    HolidaySyncBatch.run(yearsToSync());
  }
}
