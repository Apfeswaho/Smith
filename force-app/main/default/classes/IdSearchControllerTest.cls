/**
 * @description The volume test runs 40 searches, not 200: each LWC call is its own transaction, and 200 would
 *              exceed the 100-SOQL limit at 2 queries per search.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
@IsTest
private class IdSearchControllerTest {
  private static final String VALID_MALE_CITIZEN_1980 = '8001015009087';
  private static final String INVALID_CHECKSUM = '8001015009088';
  private static final Integer QUERIES_PER_SEARCH = 2;
  private static final Integer DML_PER_SEARCH = 1;

  private static List<ID_Search__c> queryIdSearches() {
    return [
      SELECT
        ID_Number__c,
        Date_Of_Birth__c,
        Gender__c,
        Citizenship_Status__c,
        Search_Count__c,
        Last_Searched__c
      FROM ID_Search__c
      ORDER BY ID_Number__c
    ];
  }

  private static String expectAuraException(String idNumber) {
    try {
      IdSearchController.search(idNumber);
      Assert.fail('search() should have thrown for input: ' + idNumber);
      return null;
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
  }

  @IsTest
  static void firstSearchCreatesRecordWithDecodedDataAndCountOne() {
    Date dateOfBirth = Date.newInstance(1995, 4, 12);
    String femaleRefugee = TestDataFactory.buildSaIdNumber(
      dateOfBirth,
      false,
      TestDataFactory.CITIZENSHIP_DIGIT_REFUGEE
    );

    Test.startTest();
    IdSearchController.SearchResult result = IdSearchController.search(
      femaleRefugee
    );
    Test.stopTest();

    List<ID_Search__c> records = queryIdSearches();
    Assert.areEqual(
      1,
      records.size(),
      'A first search should create exactly one record'
    );
    Assert.areEqual(
      femaleRefugee,
      records[0].ID_Number__c,
      'ID number should be the unique key'
    );
    Assert.areEqual(
      dateOfBirth,
      records[0].Date_Of_Birth__c,
      'Decoded date of birth should be stored'
    );
    Assert.areEqual(
      SAIdValidator.GENDER_FEMALE,
      records[0].Gender__c,
      'Decoded gender should be stored'
    );
    Assert.areEqual(
      SAIdValidator.CITIZENSHIP_REFUGEE,
      records[0].Citizenship_Status__c,
      'Decoded citizenship should be stored'
    );
    Assert.areEqual(
      1,
      records[0].Search_Count__c.intValue(),
      'First search should set the counter to 1'
    );
    Assert.isNotNull(
      records[0].Last_Searched__c,
      'Last searched timestamp should be stamped'
    );

    Assert.areEqual(
      femaleRefugee,
      result.idNumber,
      'Result should echo the ID number'
    );
    Assert.areEqual(
      dateOfBirth,
      result.dateOfBirth,
      'Result should carry the decoded date of birth'
    );
    Assert.areEqual(
      SAIdValidator.GENDER_FEMALE,
      result.gender,
      'Result should carry the decoded gender'
    );
    Assert.areEqual(
      SAIdValidator.CITIZENSHIP_REFUGEE,
      result.citizenshipStatus,
      'Result should carry the decoded citizenship'
    );
    Assert.areEqual(
      1,
      result.searchCount,
      'Result should carry the updated counter'
    );
    Assert.areEqual(
      1995,
      result.birthYear,
      'Result should expose the birth year used for the holiday lookup'
    );
  }

  @IsTest
  static void repeatSearchesIncrementCounterOnOneRecord() {
    Test.startTest();
    IdSearchController.search(VALID_MALE_CITIZEN_1980);
    IdSearchController.search(VALID_MALE_CITIZEN_1980);
    IdSearchController.SearchResult third = IdSearchController.search(
      VALID_MALE_CITIZEN_1980
    );
    Test.stopTest();

    List<ID_Search__c> records = queryIdSearches();
    Assert.areEqual(
      1,
      records.size(),
      'Repeat searches must reuse the record keyed on ID number, not duplicate it'
    );
    Assert.areEqual(
      3,
      records[0].Search_Count__c.intValue(),
      'Counter should equal the number of searches'
    );
    Assert.areEqual(
      3,
      third.searchCount,
      'Result should reflect the incremented counter'
    );
  }

  @IsTest
  static void invalidIdIsRejectedServerSideAndNothingIsPersisted() {
    Test.startTest();
    String checksumMessage = expectAuraException(INVALID_CHECKSUM);
    String nullMessage = expectAuraException(null);
    String junkMessage = expectAuraException('not-an-id');
    Test.stopTest();

    Assert.areEqual(
      SAIdValidator.ERROR_INVALID_ID,
      checksumMessage,
      'A bad checksum should surface the invalid-ID message'
    );
    Assert.areEqual(
      SAIdValidator.ERROR_INVALID_ID,
      nullMessage,
      'Null input should surface the invalid-ID message'
    );
    Assert.areEqual(
      SAIdValidator.ERROR_INVALID_ID,
      junkMessage,
      'Non-numeric input should surface the invalid-ID message'
    );
    Assert.areEqual(
      0,
      queryIdSearches().size(),
      'Invalid searches must never be persisted, regardless of client-side gating'
    );
  }

  @IsTest
  static void searchIssuesExactlyTwoQueriesAndOneDml() {
    TestDataFactory.createPublicHolidays(1980, 3);

    // Read before stopTest(), which resets limits.
    Test.startTest();
    IdSearchController.search(VALID_MALE_CITIZEN_1980);
    Integer queriesForNewRecord = Limits.getQueries();
    Integer dmlForNewRecord = Limits.getDmlStatements();
    IdSearchController.search(VALID_MALE_CITIZEN_1980);
    Integer queriesAfterRepeat = Limits.getQueries();
    Integer dmlAfterRepeat = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(
      QUERIES_PER_SEARCH,
      queriesForNewRecord,
      'A first search should cost one ID lookup plus one holiday query'
    );
    Assert.areEqual(
      DML_PER_SEARCH,
      dmlForNewRecord,
      'A first search should cost a single upsert'
    );
    Assert.areEqual(
      QUERIES_PER_SEARCH * 2,
      queriesAfterRepeat,
      'A repeat search should cost the same two queries - no extra work for the update path'
    );
    Assert.areEqual(
      DML_PER_SEARCH * 2,
      dmlAfterRepeat,
      'A repeat search should cost a single upsert'
    );
  }

  @IsTest
  static void holidaysForBirthYearAreReturnedWithBirthdayFlagged() {
    List<Public_Holiday__c> birthYearHolidays = TestDataFactory.createPublicHolidays(
      1980,
      4
    );
    TestDataFactory.createPublicHolidays(1981, 2);

    Test.startTest();
    IdSearchController.SearchResult result = IdSearchController.search(
      VALID_MALE_CITIZEN_1980
    );
    Test.stopTest();

    Assert.areEqual(
      4,
      result.holidays.size(),
      'Only the birth year\'s holidays should be returned'
    );
    Assert.areEqual(
      birthYearHolidays[0].Holiday_Name__c,
      result.holidays[0].name,
      'Holidays should be returned in date order with their names'
    );
    Assert.areEqual(
      Date.newInstance(1980, 1, 1),
      result.holidays[0].holidayDate,
      'Holiday date should be returned'
    );
    Assert.areEqual(
      'National holiday',
      result.holidays[0].holidayType,
      'Holiday type should be returned'
    );
    Assert.isTrue(
      result.holidays[0].isOnDateOfBirth,
      'The 1 Jan 1980 holiday falls on the decoded birth date and should be flagged'
    );
    Assert.isFalse(
      result.holidays[1].isOnDateOfBirth,
      'Holidays on other dates should not be flagged'
    );
    Assert.isTrue(
      result.isBirthdayOnHoliday,
      'Result should summarise that the birthday is a public holiday'
    );
  }

  @IsTest
  static void missingHolidayDataStillPersistsSearchAndReturnsEmptyList() {
    Test.startTest();
    IdSearchController.SearchResult result = IdSearchController.search(
      VALID_MALE_CITIZEN_1980
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      result.holidays.size(),
      'No cached holidays should yield an empty list, not an error'
    );
    Assert.isFalse(
      result.isBirthdayOnHoliday,
      'Birthday flag should be false when no holiday data exists'
    );
    Assert.areEqual(
      1,
      queryIdSearches().size(),
      'The search must still be recorded when holiday data is unavailable'
    );
  }

  @IsTest
  static void fortyDistinctSearchesInOneTransactionStayWithinLimits() {
    Integer searchCount = 40;
    List<String> idNumbers = new List<String>();
    for (Integer i = 0; i < searchCount; i++) {
      idNumbers.add(
        TestDataFactory.buildSaIdNumber(
          Date.newInstance(1988, 8, 8),
          Math.mod(i, 2) == 0,
          Math.mod(i, 3),
          i
        )
      );
    }

    Test.startTest();
    for (String idNumber : idNumbers) {
      IdSearchController.search(idNumber);
    }
    Integer queriesUsed = Limits.getQueries();
    Integer dmlUsed = Limits.getDmlStatements();
    Test.stopTest();

    List<ID_Search__c> records = queryIdSearches();
    Assert.areEqual(
      searchCount,
      records.size(),
      'Every distinct ID should get its own record'
    );
    for (ID_Search__c record : records) {
      Assert.areEqual(
        1,
        record.Search_Count__c.intValue(),
        'Each distinct ID should have been counted once: ' + record.ID_Number__c
      );
    }
    Assert.areEqual(
      searchCount * QUERIES_PER_SEARCH,
      queriesUsed,
      'Query cost should scale linearly at two per search'
    );
    Assert.areEqual(
      searchCount * DML_PER_SEARCH,
      dmlUsed,
      'DML cost should scale linearly at one per search'
    );
  }

  @IsTest
  static void userWithGuestPermissionSetCanSearch() {
    User restrictedUser = TestDataFactory.createRestrictedUser();
    TestDataFactory.assignPermissionSet(
      restrictedUser.Id,
      TestDataFactory.PERMISSION_SET_GUEST_ACCESS
    );
    TestDataFactory.createPublicHolidays(1980, 2);

    Test.startTest();
    IdSearchController.SearchResult result;
    System.runAs(restrictedUser) {
      result = IdSearchController.search(VALID_MALE_CITIZEN_1980);
      result = IdSearchController.search(VALID_MALE_CITIZEN_1980);
    }
    Test.stopTest();

    List<ID_Search__c> records = queryIdSearches();
    Assert.areEqual(
      2,
      result.searchCount,
      'A user holding only the guest permission set should be able to record and repeat a search'
    );
    Assert.areEqual(
      2,
      result.holidays.size(),
      'A user holding only the guest permission set should be able to read cached holidays'
    );
    Assert.areEqual(
      1,
      records.size(),
      'Without sharing, the repeat search must find the record it does not own'
    );
    Assert.areEqual(
      2,
      records[0].Search_Count__c.intValue(),
      'Counter should increment for a non-owning user'
    );
  }

  @IsTest
  static void userWithoutGuestPermissionSetIsRefusedBeforeAnyDml() {
    User restrictedUser = TestDataFactory.createRestrictedUser();

    Test.startTest();
    String message;
    System.runAs(restrictedUser) {
      message = expectAuraException(VALID_MALE_CITIZEN_1980);
    }
    Test.stopTest();

    Assert.areEqual(
      IdSearchController.ERROR_NO_ACCESS,
      message,
      'Without object access the search should be refused with the no-access message'
    );
    Assert.areEqual(
      0,
      queryIdSearches().size(),
      'A refused search must not write anything'
    );
  }
}
