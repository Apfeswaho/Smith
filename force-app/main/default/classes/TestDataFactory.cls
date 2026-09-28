/**
 * @description Shared test data. buildSaIdNumber() mints valid IDs so tests don't hard-code real-looking ones.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
@IsTest
public class TestDataFactory {
  public static final Integer CITIZENSHIP_DIGIT_CITIZEN = 0;
  public static final Integer CITIZENSHIP_DIGIT_PERMANENT_RESIDENT = 1;
  public static final Integer CITIZENSHIP_DIGIT_REFUGEE = 2;
  public static final String PERMISSION_SET_GUEST_ACCESS = 'ID_Search_Guest_Access';
  // Must match the deployed Calendarific_Holidays path.
  public static final String CALENDARIFIC_PATH = '/holidays?api_key={apiKey}&country=ZA&year={year}&type=national';

  private static final Integer MALE_SEQUENCE_OFFSET = 5000;
  private static final String LEGACY_RACE_DIGIT = '8';
  private static final List<String> RESTRICTED_PROFILE_NAMES = new List<String>{
    'Minimum Access - Salesforce',
    'Standard User'
  };

  public static String buildSaIdNumber(
    Date dateOfBirth,
    Boolean isMale,
    Integer citizenshipDigit
  ) {
    return buildSaIdNumber(dateOfBirth, isMale, citizenshipDigit, 0);
  }

  /**
   * @param sequence 0-4999, for distinct IDs on the same birth date
   */
  public static String buildSaIdNumber(
    Date dateOfBirth,
    Boolean isMale,
    Integer citizenshipDigit,
    Integer sequence
  ) {
    String genderSequence = String.valueOf(
        (isMale ? MALE_SEQUENCE_OFFSET : 0) + sequence
      )
      .leftPad(4, '0');
    String firstTwelveDigits =
      String.valueOf(dateOfBirth.year()).right(2) +
      String.valueOf(dateOfBirth.month()).leftPad(2, '0') +
      String.valueOf(dateOfBirth.day()).leftPad(2, '0') +
      genderSequence +
      String.valueOf(citizenshipDigit) +
      LEGACY_RACE_DIGIT;
    return firstTwelveDigits + luhnCheckDigit(firstTwelveDigits);
  }

  public static Integer luhnCheckDigit(String firstTwelveDigits) {
    Integer sum = 0;
    Boolean doubleThisDigit = true;
    for (Integer i = firstTwelveDigits.length() - 1; i >= 0; i--) {
      Integer digit = Integer.valueOf(firstTwelveDigits.substring(i, i + 1));
      if (doubleThisDigit) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }
      sum += digit;
      doubleThisDigit = !doubleThisDigit;
    }
    return Math.mod(10 - Math.mod(sum, 10), 10);
  }

  // In-memory setting, because custom metadata can't be inserted in tests.
  public static Web_Service_Setting__mdt useCalendarificSetting(String apiKey) {
    Web_Service_Setting__mdt setting = new Web_Service_Setting__mdt(
      DeveloperName = CalendarificService.SETTING_DEVELOPER_NAME,
      Named_Credential__c = 'Calendarific',
      Path__c = CALENDARIFIC_PATH,
      Http_Method__c = 'GET',
      Timeout_Ms__c = 30000,
      Api_Key__c = apiKey
    );
    WebServiceSettings.settingOverrides.put(
      CalendarificService.SETTING_DEVELOPER_NAME,
      setting
    );
    return setting;
  }

  public static List<Public_Holiday__c> createPublicHolidays(
    Integer year,
    Integer count
  ) {
    List<Public_Holiday__c> holidays = new List<Public_Holiday__c>();
    for (Integer i = 0; i < count; i++) {
      Date holidayDate = Date.newInstance(year, 1, 1).addDays(i * 7);
      holidays.add(
        new Public_Holiday__c(
          Name = 'Holiday ' + i,
          Holiday_Name__c = 'Holiday ' + i,
          Holiday_Date__c = holidayDate,
          Holiday_Type__c = 'National holiday',
          Year__c = year,
          External_Key__c = 'ZA-' +
            String.valueOf(holidayDate) +
            '-holiday-' +
            i
        )
      );
    }
    insert holidays;
    return holidays;
  }

  // Stand-in for the site guest user, which can't be created in tests. runAs lets callers mix setup and other DML.
  public static User createRestrictedUser() {
    Profile restrictedProfile = [
      SELECT Id
      FROM Profile
      WHERE Name IN :RESTRICTED_PROFILE_NAMES
      ORDER BY Name
      LIMIT 1
    ];
    String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()))
      .right(6);
    User restrictedUser = new User(
      ProfileId = restrictedProfile.Id,
      Alias = 'rst' + uniqueSuffix.right(5),
      Username = 'restricted.' + uniqueSuffix + '@idsearch.test.invalid',
      Email = 'restricted@idsearch.test.invalid',
      LastName = 'Restricted',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_ZA',
      TimeZoneSidKey = 'Africa/Johannesburg'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert restrictedUser;
    }
    return restrictedUser;
  }

  public static void assignPermissionSet(Id userId, String permissionSetName) {
    PermissionSet permissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permissionSetName
      LIMIT 1
    ];
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new PermissionSetAssignment(
        AssigneeId = userId,
        PermissionSetId = permissionSet.Id
      );
    }
  }
}
