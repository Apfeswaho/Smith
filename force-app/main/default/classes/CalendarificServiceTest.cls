/**
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
@IsTest
private class CalendarificServiceTest {
  private static final Integer YEAR = 2024;
  private static final String TEST_API_KEY = 'test-api-key';

  @IsTest
  static void wellFormedResponseIsParsedIntoHolidays() {
    TestDataFactory.useCalendarificSetting(TEST_API_KEY);
    CalendarificCalloutMock mock = CalendarificCalloutMock.success(YEAR, 3);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    List<CalendarificService.Holiday> holidays = CalendarificService.fetchHolidays(
      YEAR
    );
    // Read before stopTest(), which resets limits.
    Integer calloutsUsed = Limits.getCallouts();
    Test.stopTest();

    Assert.areEqual(
      3,
      holidays.size(),
      'Every holiday in the payload should be returned'
    );
    Assert.areEqual(
      'Sample Holiday 0',
      holidays[0].name,
      'Holiday name should come from the "name" attribute'
    );
    Assert.areEqual(
      Date.newInstance(YEAR, 1, 1),
      holidays[0].holidayDate,
      'Holiday date should be built from date.datetime parts'
    );
    Assert.areEqual(
      'National holiday',
      holidays[0].primaryType,
      'Primary type should be captured'
    );
    Assert.areEqual(
      1,
      mock.requests.size(),
      'Exactly one callout should be made per fetch'
    );
    Assert.areEqual(
      1,
      calloutsUsed,
      'Exactly one callout should be counted against limits per fetch'
    );
  }

  @IsTest
  static void requestTargetsNamedCredentialWithKeyCountryYearAndNationalFilter() {
    TestDataFactory.useCalendarificSetting('key with space');
    CalendarificCalloutMock mock = CalendarificCalloutMock.success(YEAR, 1);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    CalendarificService.fetchHolidays(YEAR);
    Test.stopTest();

    String endpoint = mock.requests[0].getEndpoint();
    Assert.isTrue(
      endpoint.startsWith('callout:Calendarific/holidays?'),
      'Endpoint should route through the Calendarific Named Credential, got ' +
      endpoint
    );
    Assert.isTrue(
      endpoint.contains('api_key=key+with+space'),
      'API key should be URL-encoded as a query parameter, got ' + endpoint
    );
    Assert.isTrue(
      endpoint.contains('country=ZA'),
      'Country should be South Africa, got ' + endpoint
    );
    Assert.isTrue(
      endpoint.contains('year=' + YEAR),
      'Requested year should be passed through, got ' + endpoint
    );
    Assert.isTrue(
      endpoint.contains('type=national'),
      'Only public (national) holidays should be requested, got ' + endpoint
    );
    Assert.areEqual(
      'GET',
      mock.requests[0].getMethod(),
      'Holidays endpoint is a GET'
    );
  }

  @IsTest
  static void missingApiKeyFailsBeforeAnyCallout() {
    TestDataFactory.useCalendarificSetting('');
    CalendarificCalloutMock mock = CalendarificCalloutMock.success(YEAR, 1);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    try {
      CalendarificService.fetchHolidays(YEAR);
      Assert.fail('A blank API key should raise SettingException');
    } catch (WebServiceSettings.SettingException e) {
      Assert.isTrue(
        e.getMessage().contains(CalendarificService.SETTING_DEVELOPER_NAME) &&
        e.getMessage().contains('API Key'),
        'Message should name the setting record that is missing its key, got: ' +
        e.getMessage()
      );
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      mock.requests.size(),
      'No callout should be attempted without a key'
    );
  }

  @IsTest
  static void non200StatusRaisesExceptionInsteadOfEmptyList() {
    TestDataFactory.useCalendarificSetting(TEST_API_KEY);
    Test.setMock(
      HttpCalloutMock.class,
      new CalendarificCalloutMock(
        401,
        'Unauthorized',
        '{"meta":{"code":401,"error_type":"unauthorized"}}'
      )
    );

    Test.startTest();
    try {
      CalendarificService.fetchHolidays(YEAR);
      Assert.fail('A 401 should raise CalendarificException');
    } catch (CalendarificService.CalendarificException e) {
      Assert.isTrue(
        e.getMessage().contains('401'),
        'Message should include the HTTP status code, got: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void rateLimitedStatusRaisesException() {
    TestDataFactory.useCalendarificSetting(TEST_API_KEY);
    Test.setMock(
      HttpCalloutMock.class,
      new CalendarificCalloutMock(429, 'Too Many Requests', '')
    );

    Test.startTest();
    try {
      CalendarificService.fetchHolidays(YEAR);
      Assert.fail('A 429 should raise CalendarificException');
    } catch (CalendarificService.CalendarificException e) {
      Assert.isTrue(
        e.getMessage().contains('429'),
        'Message should include the HTTP status code, got: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void malformedJsonRaisesCalendarificException() {
    TestDataFactory.useCalendarificSetting(TEST_API_KEY);
    Test.setMock(
      HttpCalloutMock.class,
      new CalendarificCalloutMock(200, 'OK', '<html>not json</html>')
    );

    Test.startTest();
    try {
      CalendarificService.fetchHolidays(YEAR);
      Assert.fail('Malformed JSON should raise CalendarificException');
    } catch (CalendarificService.CalendarificException e) {
      Assert.isTrue(
        e.getMessage()
          .startsWith(
            CalendarificService.ERROR_MALFORMED_RESPONSE.substringBefore('{0}')
          ),
        'Parse failures should be wrapped in the malformed-response message, got: ' +
        e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void unexpectedJsonShapeRaisesCalendarificException() {
    try {
      CalendarificService.parseHolidays('{"meta":{"code":200},"response":{}}');
      Assert.fail(
        'A payload without a holidays array should raise CalendarificException'
      );
    } catch (CalendarificService.CalendarificException e) {
      Assert.isTrue(
        e.getMessage().contains('could not be parsed'),
        'Shape problems should be reported as parse failures, got: ' +
        e.getMessage()
      );
    }

    try {
      CalendarificService.parseHolidays(
        '{"response":{"holidays":[{"name":"No date"}]}}'
      );
      Assert.fail(
        'A holiday without a date should raise CalendarificException'
      );
    } catch (CalendarificService.CalendarificException e) {
      Assert.isTrue(
        e.getMessage().contains('could not be parsed'),
        'Missing date should be reported as a parse failure, got: ' +
        e.getMessage()
      );
    }
  }

  @IsTest
  static void isoDateIsUsedWhenDatetimePartsAreAbsent() {
    List<CalendarificService.Holiday> holidays = CalendarificService.parseHolidays(
      '{"response":{"holidays":[{"name":"Iso only","primary_type":"National holiday","date":{"iso":"2024-12-25T00:00:00+02:00"}}]}}'
    );

    Assert.areEqual(
      Date.newInstance(2024, 12, 25),
      holidays[0].holidayDate,
      'The date portion of the iso value should be used as a fallback'
    );
  }
}
