/**
 * @author Apfeswaho Tshivhase
 * @date 2026-09-22
 */
@IsTest
private class WebServiceSettingsTest {
  private static final String SETTING_NAME = 'Test_Service';

  private static Web_Service_Setting__mdt registerSetting(
    String path,
    String apiKey
  ) {
    Web_Service_Setting__mdt setting = new Web_Service_Setting__mdt(
      DeveloperName = SETTING_NAME,
      Named_Credential__c = 'Calendarific',
      Path__c = path,
      Http_Method__c = 'GET',
      Timeout_Ms__c = 45000,
      Api_Key__c = apiKey
    );
    WebServiceSettings.settingOverrides.put(SETTING_NAME, setting);
    return setting;
  }

  @IsTest
  static void callerPlaceholdersAndApiKeyAreMergedIntoEndpoint() {
    registerSetting('/holidays?api_key={apiKey}&year={year}', 'secret');

    HttpRequest request = WebServiceSettings.buildRequest(
      SETTING_NAME,
      new Map<String, String>{ 'year' => '1994' }
    );

    Assert.areEqual(
      'callout:Calendarific/holidays?api_key=secret&year=1994',
      request.getEndpoint(),
      'Named Credential, record key and caller-supplied year should all be merged into the endpoint'
    );
    Assert.areEqual(
      'GET',
      request.getMethod(),
      'HTTP method should come from the record'
    );
  }

  @IsTest
  static void mergedValuesAreUrlEncoded() {
    registerSetting('/search?q={term}&api_key={apiKey}', 'k&y');

    HttpRequest request = WebServiceSettings.buildRequest(
      SETTING_NAME,
      new Map<String, String>{ 'term' => 'a b&c' }
    );

    Assert.areEqual(
      'callout:Calendarific/search?q=a+b%26c&api_key=k%26y',
      request.getEndpoint(),
      'Every merged value should be URL-encoded so it cannot break the query string'
    );
  }

  @IsTest
  static void placeholderUsedTwiceIsReplacedEverywhere() {
    registerSetting('/{year}/holidays?year={year}', null);

    HttpRequest request = WebServiceSettings.buildRequest(
      SETTING_NAME,
      new Map<String, String>{ 'year' => '2024' }
    );

    Assert.areEqual(
      'callout:Calendarific/2024/holidays?year=2024',
      request.getEndpoint(),
      'A placeholder appearing more than once should be replaced at every position'
    );
  }

  @IsTest
  static void unresolvedPlaceholderFailsLoudly() {
    registerSetting('/holidays?year={year}&location={location}', null);

    try {
      WebServiceSettings.buildRequest(
        SETTING_NAME,
        new Map<String, String>{ 'year' => '2024' }
      );
      Assert.fail(
        'A placeholder the caller did not supply should raise SettingException'
      );
    } catch (WebServiceSettings.SettingException e) {
      Assert.isTrue(
        e.getMessage().contains('{location}') &&
        e.getMessage().contains(SETTING_NAME),
        'Message should name the setting and the unresolved placeholder, got: ' +
        e.getMessage()
      );
    }
  }

  @IsTest
  static void blankApiKeyFailsWhenPathUsesApiKeyPlaceholder() {
    registerSetting('/holidays?api_key={apiKey}', '');

    try {
      WebServiceSettings.buildRequest(SETTING_NAME, new Map<String, String>());
      Assert.fail(
        'A path that needs {apiKey} with a blank key should raise SettingException'
      );
    } catch (WebServiceSettings.SettingException e) {
      Assert.areEqual(
        String.format(
          WebServiceSettings.ERROR_MISSING_API_KEY,
          new List<String>{ SETTING_NAME, '{apiKey}' }
        ),
        e.getMessage(),
        'Message should point the admin at the record missing its key'
      );
    }
  }

  @IsTest
  static void blankApiKeyIsFineWhenPathDoesNotUseIt() {
    registerSetting('/public/holidays?year={year}', null);

    HttpRequest request = WebServiceSettings.buildRequest(
      SETTING_NAME,
      new Map<String, String>{ 'year' => '2024' }
    );

    Assert.areEqual(
      'callout:Calendarific/public/holidays?year=2024',
      request.getEndpoint(),
      'Services without a key should not be forced to configure one'
    );
  }

  @IsTest
  static void methodAndTimeoutDefaultWhenBlank() {
    Web_Service_Setting__mdt setting = registerSetting('/ping', null);
    setting.Http_Method__c = null;
    setting.Timeout_Ms__c = null;

    HttpRequest request = WebServiceSettings.buildRequest(SETTING_NAME, null);

    Assert.areEqual('GET', request.getMethod(), 'Method should default to GET');
  }

  @IsTest
  static void unknownSettingFailsWithConfigurationMessage() {
    try {
      WebServiceSettings.buildRequest(
        'Does_Not_Exist',
        new Map<String, String>()
      );
      Assert.fail('An unknown developer name should raise SettingException');
    } catch (WebServiceSettings.SettingException e) {
      Assert.isTrue(
        e.getMessage().contains('Does_Not_Exist'),
        'Message should name the missing record, got: ' + e.getMessage()
      );
    }
  }

  @IsTest
  static void deployedCalendarificRecordHasExpectedShape() {
    // Reads the deployed record to catch a broken template before production.
    Web_Service_Setting__mdt setting = WebServiceSettings.getSetting(
      CalendarificService.SETTING_DEVELOPER_NAME
    );

    Assert.areEqual(
      'Calendarific',
      setting.Named_Credential__c,
      'Record should point at the Calendarific Named Credential'
    );
    Assert.isTrue(
      setting.Path__c.contains('{apiKey}') &&
      setting.Path__c.contains('{year}'),
      'Deployed path must carry the {apiKey} and {year} placeholders, got: ' +
      setting.Path__c
    );
    Assert.isTrue(
      setting.Path__c.contains('country=ZA') &&
      setting.Path__c.contains('type=national'),
      'Deployed path should request South African national holidays, got: ' +
      setting.Path__c
    );
  }
}
