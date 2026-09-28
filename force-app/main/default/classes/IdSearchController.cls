/**
 * @description Guest entry point for the SA ID search page: re-validates the ID, records the search and returns
 *              the cached holidays for the birth year. No callout.
 *
 *              Without sharing on purpose: guests don't own the records they create, so a sharing-enforced
 *              lookup would never find a repeat search. Exposure is limited to the submitted ID number and
 *              gated by ensureRunningUserCanSearch().
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
public without sharing class IdSearchController {
  public static final String ERROR_NO_ACCESS = 'You do not have permission to run an ID search.';

  private static final String EXISTING_SEARCH_QUERY = 'SELECT Id, Search_Count__c FROM ID_Search__c WHERE ID_Number__c = :idNumber LIMIT 1';

  private static final List<Schema.SObjectField> ID_SEARCH_WRITTEN_FIELDS = new List<Schema.SObjectField>{
    ID_Search__c.ID_Number__c,
    ID_Search__c.Date_Of_Birth__c,
    ID_Search__c.Gender__c,
    ID_Search__c.Citizenship_Status__c,
    ID_Search__c.Search_Count__c,
    ID_Search__c.Last_Searched__c
  };

  public class SearchException extends Exception {
  }

  public class SearchResult {
    @AuraEnabled
    public String idNumber;
    @AuraEnabled
    public Date dateOfBirth;
    @AuraEnabled
    public String gender;
    @AuraEnabled
    public String citizenshipStatus;
    @AuraEnabled
    public Integer searchCount;
    @AuraEnabled
    public Integer birthYear;
    @AuraEnabled
    public Boolean isBirthdayOnHoliday = false;
    @AuraEnabled
    public List<HolidayResult> holidays = new List<HolidayResult>();
  }

  public class HolidayResult {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date holidayDate;
    @AuraEnabled
    public String holidayType;
    @AuraEnabled
    public Boolean isOnDateOfBirth;
  }

  @AuraEnabled
  public static SearchResult search(String idNumber) {
    try {
      ensureRunningUserCanSearch();
      SAIdValidator.ParsedId parsed = SAIdValidator.parse(idNumber);
      ID_Search__c record = recordSearch(parsed);
      return buildResult(record, parsed);
    } catch (Exception e) {
      throw toAuraException(e.getMessage());
    }
  }

  private static ID_Search__c recordSearch(SAIdValidator.ParsedId parsed) {
    // System mode: guests can't read or update the records they create.
    List<ID_Search__c> existing = Database.queryWithBinds(
      EXISTING_SEARCH_QUERY,
      new Map<String, Object>{ 'idNumber' => parsed.idNumber },
      AccessLevel.SYSTEM_MODE
    );
    ID_Search__c record = existing.isEmpty()
      ? new ID_Search__c(Search_Count__c = 0)
      : existing[0];
    // Upsert needs the external ID set, even on an existing row.
    record.ID_Number__c = parsed.idNumber;
    record.Date_Of_Birth__c = parsed.dateOfBirth;
    record.Gender__c = parsed.gender;
    record.Citizenship_Status__c = parsed.citizenshipStatus;
    record.Search_Count__c =
      (record.Search_Count__c == null ? 0 : record.Search_Count__c) + 1;
    record.Last_Searched__c = Datetime.now();
    // Concurrent first searches don't collide; a lost increment under concurrency is accepted.
    Database.upsert(
      record,
      ID_Search__c.ID_Number__c,
      true,
      AccessLevel.SYSTEM_MODE
    );
    return record;
  }

  private static SearchResult buildResult(
    ID_Search__c record,
    SAIdValidator.ParsedId parsed
  ) {
    SearchResult result = new SearchResult();
    result.idNumber = parsed.idNumber;
    result.dateOfBirth = parsed.dateOfBirth;
    result.gender = parsed.gender;
    result.citizenshipStatus = parsed.citizenshipStatus;
    result.searchCount = record.Search_Count__c.intValue();
    result.birthYear = parsed.dateOfBirth.year();

    for (Public_Holiday__c holiday : queryHolidays(result.birthYear)) {
      HolidayResult holidayResult = new HolidayResult();
      holidayResult.name = holiday.Holiday_Name__c;
      holidayResult.holidayDate = holiday.Holiday_Date__c;
      holidayResult.holidayType = holiday.Holiday_Type__c;
      holidayResult.isOnDateOfBirth =
        holiday.Holiday_Date__c == parsed.dateOfBirth;
      result.isBirthdayOnHoliday =
        result.isBirthdayOnHoliday || holidayResult.isOnDateOfBirth;
      result.holidays.add(holidayResult);
    }
    return result;
  }

  private static List<Public_Holiday__c> queryHolidays(Integer year) {
    return [
      SELECT Holiday_Name__c, Holiday_Date__c, Holiday_Type__c
      FROM Public_Holiday__c
      WHERE Year__c = :year
      WITH SYSTEM_MODE
      ORDER BY Holiday_Date__c ASC
    ];
  }

  private static void ensureRunningUserCanSearch() {
    Schema.DescribeSObjectResult idSearchDescribe = ID_Search__c.SObjectType.getDescribe();
    // Create is the most a guest can hold, so it gates the search; the increment runs in system mode.
    Boolean canRecordSearch = idSearchDescribe.isCreateable();
    for (Schema.SObjectField field : ID_SEARCH_WRITTEN_FIELDS) {
      canRecordSearch = canRecordSearch && field.getDescribe().isCreateable();
    }
    if (
      !canRecordSearch ||
      !Public_Holiday__c.SObjectType.getDescribe().isAccessible()
    ) {
      throw new SearchException(ERROR_NO_ACCESS);
    }
  }

  // The message only reaches the client when set explicitly.
  private static AuraHandledException toAuraException(String message) {
    AuraHandledException auraException = new AuraHandledException(message);
    auraException.setMessage(message);
    return auraException;
  }
}
