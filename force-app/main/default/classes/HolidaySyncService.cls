/**
 * @description Syncs one year of Calendarific holidays into Public_Holiday__c and logs every run to
 *              Integration_Log__c. Internal context only; the guest site never triggers it.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
public with sharing class HolidaySyncService {
  public static final String PROCESS_NAME = 'Calendarific Holiday Sync';
  // Must match the country in the Calendarific_Holidays path.
  public static final String EXTERNAL_KEY_COUNTRY_PREFIX = 'ZA';
  public static final String STATUS_SUCCESS = 'Success';
  public static final String STATUS_FAILED = 'Failed';

  private static final Integer NAME_FIELD_MAX_LENGTH = 80;
  private static final Integer EXTERNAL_KEY_MAX_LENGTH = 255;

  public class SyncResult {
    public Integer year;
    public Integer holidayCount = 0;
    public Boolean isSuccess = false;
    public String errorMessage;
  }

  public static SyncResult syncYear(Integer year) {
    SyncResult result = new SyncResult();
    result.year = year;
    try {
      List<Public_Holiday__c> holidays = toRecords(
        CalendarificService.fetchHolidays(year)
      );
      upsert holidays External_Key__c;
      result.holidayCount = holidays.size();
      result.isSuccess = true;
    } catch (Exception e) {
      result.errorMessage = e.getTypeName() + ': ' + e.getMessage();
    }
    logResult(result);
    return result;
  }

  @TestVisible
  private static List<Public_Holiday__c> toRecords(
    List<CalendarificService.Holiday> holidays
  ) {
    List<Public_Holiday__c> records = new List<Public_Holiday__c>();
    for (CalendarificService.Holiday holiday : holidays) {
      records.add(
        new Public_Holiday__c(
          Name = holiday.name.abbreviate(NAME_FIELD_MAX_LENGTH),
          Holiday_Name__c = holiday.name,
          Holiday_Date__c = holiday.holidayDate,
          Holiday_Type__c = holiday.primaryType,
          Year__c = holiday.holidayDate.year(),
          External_Key__c = buildExternalKey(holiday)
        )
      );
    }
    return records;
  }

  // Includes the name because two holidays can share a date.
  @TestVisible
  private static String buildExternalKey(CalendarificService.Holiday holiday) {
    String slug = holiday.name.toLowerCase()
      .replaceAll('[^a-z0-9]+', '-')
      .removeStart('-')
      .removeEnd('-');
    return (EXTERNAL_KEY_COUNTRY_PREFIX +
      '-' +
      String.valueOf(holiday.holidayDate) +
      '-' +
      slug)
      .left(EXTERNAL_KEY_MAX_LENGTH);
  }

  private static void logResult(SyncResult result) {
    insert new Integration_Log__c(
      Process__c = PROCESS_NAME,
      Status__c = result.isSuccess ? STATUS_SUCCESS : STATUS_FAILED,
      Year__c = result.year,
      Record_Count__c = result.holidayCount,
      Message__c = result.isSuccess
        ? 'Upserted ' + result.holidayCount + ' holidays for ' + result.year
        : result.errorMessage
    );
  }
}
