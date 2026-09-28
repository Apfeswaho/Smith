/**
 * @description Vectors are shared with saIdNumber.test.js; change both together. 8001015009087 is the widely
 *              published valid example.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
@IsTest
private class SAIdValidatorTest {
  private static final String VALID_MALE_CITIZEN_1980 = '8001015009087';
  private static final String VALID_FEMALE_CITIZEN_1990 = '9002200472089';
  private static final String VALID_MALE_PERMANENT_RESIDENT_1985 = '8512315123188';
  private static final String VALID_FEMALE_REFUGEE_2001 = '0107152345289';
  private static final String VALID_FEMALE_LEAP_DAY_2000 = '0002290001086';
  private static final String VALID_FEMALE_SEQUENCE_4999 = '7506154999089';
  private static final String VALID_MALE_SEQUENCE_5000 = '7506155000085';
  private static final String INVALID_CHECKSUM_OFF_BY_ONE = '8001015009088';
  private static final String INVALID_MONTH_13_CHECKSUM_OK = '9913015800084';
  private static final String INVALID_FEB_30_CHECKSUM_OK = '9902305800086';
  private static final String INVALID_FEB_29_NON_LEAP_CHECKSUM_OK = '9902290001088';
  private static final String INVALID_DAY_00_CHECKSUM_OK = '8001005009089';
  private static final String INVALID_CITIZENSHIP_3_CHECKSUM_OK = '8001015009384';

  @IsTest
  static void publishedExampleDecodesToMaleCitizenBornFirstJan1980() {
    SAIdValidator.ParsedId parsed = SAIdValidator.parse(
      VALID_MALE_CITIZEN_1980
    );

    Assert.areEqual(
      Date.newInstance(1980, 1, 1),
      parsed.dateOfBirth,
      'Digits 1-6 (800101) should decode to 1 Jan 1980'
    );
    Assert.areEqual(
      SAIdValidator.GENDER_MALE,
      parsed.gender,
      'Sequence 5009 is in the male range (5000-9999)'
    );
    Assert.areEqual(
      SAIdValidator.CITIZENSHIP_CITIZEN,
      parsed.citizenshipStatus,
      'Citizenship digit 0 should decode to SA Citizen'
    );
    Assert.areEqual(
      VALID_MALE_CITIZEN_1980,
      parsed.idNumber,
      'Parsed result should echo the normalised ID number'
    );
  }

  @IsTest
  static void everyCitizenshipDigitDecodes() {
    Assert.areEqual(
      SAIdValidator.CITIZENSHIP_CITIZEN,
      SAIdValidator.parse(VALID_FEMALE_CITIZEN_1990).citizenshipStatus,
      'Citizenship digit 0 should decode to SA Citizen'
    );
    Assert.areEqual(
      SAIdValidator.CITIZENSHIP_PERMANENT_RESIDENT,
      SAIdValidator.parse(VALID_MALE_PERMANENT_RESIDENT_1985).citizenshipStatus,
      'Citizenship digit 1 should decode to Permanent Resident'
    );
    Assert.areEqual(
      SAIdValidator.CITIZENSHIP_REFUGEE,
      SAIdValidator.parse(VALID_FEMALE_REFUGEE_2001).citizenshipStatus,
      'Citizenship digit 2 should decode to Refugee'
    );
  }

  @IsTest
  static void genderBoundaryIsBetween4999And5000() {
    Assert.areEqual(
      SAIdValidator.GENDER_FEMALE,
      SAIdValidator.parse(VALID_FEMALE_SEQUENCE_4999).gender,
      'Sequence 4999 is the top of the female range'
    );
    Assert.areEqual(
      SAIdValidator.GENDER_MALE,
      SAIdValidator.parse(VALID_MALE_SEQUENCE_5000).gender,
      'Sequence 5000 is the bottom of the male range'
    );
  }

  @IsTest
  static void twoThousandsBirthDatesDecodeWithLeapDay() {
    Assert.areEqual(
      Date.newInstance(2000, 2, 29),
      SAIdValidator.parse(VALID_FEMALE_LEAP_DAY_2000).dateOfBirth,
      'YY=00 should infer 2000 (a leap year), making 29 Feb valid'
    );
    Assert.areEqual(
      Date.newInstance(2001, 7, 15),
      SAIdValidator.parse(VALID_FEMALE_REFUGEE_2001).dateOfBirth,
      'YY=01 should infer 2001'
    );
  }

  @IsTest
  static void centuryInferenceNeverPlacesBirthInTheFuture() {
    Integer currentYear = Date.today().year();
    String idForThisYear = TestDataFactory.buildSaIdNumber(
      Date.newInstance(currentYear, 3, 4),
      true,
      TestDataFactory.CITIZENSHIP_DIGIT_CITIZEN
    );
    String idWithNextYearsDigits = TestDataFactory.buildSaIdNumber(
      Date.newInstance(currentYear + 1, 3, 4),
      true,
      TestDataFactory.CITIZENSHIP_DIGIT_CITIZEN
    );

    Assert.areEqual(
      currentYear,
      SAIdValidator.parse(idForThisYear).dateOfBirth.year(),
      'A YY equal to the current year should resolve to the current century'
    );
    Assert.areEqual(
      currentYear - 99,
      SAIdValidator.parse(idWithNextYearsDigits).dateOfBirth.year(),
      'A YY one past the current year cannot be in the future, so it should resolve to the previous century'
    );
  }

  @IsTest
  static void checksumOffByOneIsInvalid() {
    Assert.isTrue(
      SAIdValidator.isValid(VALID_MALE_CITIZEN_1980),
      'Control: the unaltered published example should be valid'
    );
    Assert.isFalse(
      SAIdValidator.isValid(INVALID_CHECKSUM_OFF_BY_ONE),
      'Altering the check digit by one should fail the Luhn checksum'
    );
  }

  @IsTest
  static void impossibleCalendarDatesAreInvalidEvenWhenChecksumPasses() {
    Assert.isFalse(
      SAIdValidator.isValid(INVALID_MONTH_13_CHECKSUM_OK),
      'Month 13 should be rejected even though the Luhn digit is correct'
    );
    Assert.isFalse(
      SAIdValidator.isValid(INVALID_FEB_30_CHECKSUM_OK),
      '30 February should be rejected even though the Luhn digit is correct'
    );
    Assert.isFalse(
      SAIdValidator.isValid(INVALID_FEB_29_NON_LEAP_CHECKSUM_OK),
      '29 February 1999 (not a leap year) should be rejected'
    );
    Assert.isFalse(
      SAIdValidator.isValid(INVALID_DAY_00_CHECKSUM_OK),
      'Day 00 should be rejected even though the Luhn digit is correct'
    );
  }

  @IsTest
  static void unknownCitizenshipDigitIsInvalidEvenWhenChecksumPasses() {
    Assert.isFalse(
      SAIdValidator.isValid(INVALID_CITIZENSHIP_3_CHECKSUM_OK),
      'Citizenship digit 3 is undefined and should be rejected'
    );
  }

  @IsTest
  static void wrongLengthOrNonNumericInputIsInvalidWithoutThrowing() {
    Assert.isFalse(
      SAIdValidator.isValid(null),
      'Null should be invalid, not an exception'
    );
    Assert.isFalse(SAIdValidator.isValid(''), 'Empty string should be invalid');
    Assert.isFalse(
      SAIdValidator.isValid('   '),
      'Whitespace-only should be invalid'
    );
    Assert.isFalse(
      SAIdValidator.isValid('800101500908'),
      '12 digits should be invalid'
    );
    Assert.isFalse(
      SAIdValidator.isValid('80010150090871'),
      '14 digits should be invalid'
    );
    Assert.isFalse(
      SAIdValidator.isValid('80010150O9087'),
      'A letter O in place of a zero should be invalid'
    );
    Assert.isFalse(
      SAIdValidator.isValid('8001-015-00908'),
      'Punctuation should be invalid'
    );
  }

  @IsTest
  static void surroundingWhitespaceIsTrimmedBeforeValidation() {
    SAIdValidator.ParsedId parsed = SAIdValidator.parse(
      '  ' + VALID_MALE_CITIZEN_1980 + '\n'
    );

    Assert.areEqual(
      VALID_MALE_CITIZEN_1980,
      parsed.idNumber,
      'Leading/trailing whitespace from a pasted value should be ignored'
    );
  }

  @IsTest
  static void parseThrowsInvalidIdExceptionForInvalidInput() {
    try {
      SAIdValidator.parse(INVALID_CHECKSUM_OFF_BY_ONE);
      Assert.fail('parse() should throw for an invalid ID number');
    } catch (SAIdValidator.InvalidIdException e) {
      Assert.areEqual(
        SAIdValidator.ERROR_INVALID_ID,
        e.getMessage(),
        'The exception should carry the user-facing invalid-ID message'
      );
    }
  }

  @IsTest
  static void factoryGeneratedIdsRoundTripThroughParse() {
    Date dateOfBirth = Date.newInstance(1993, 11, 5);
    String femaleRefugee = TestDataFactory.buildSaIdNumber(
      dateOfBirth,
      false,
      TestDataFactory.CITIZENSHIP_DIGIT_REFUGEE,
      123
    );
    String malePermanentResident = TestDataFactory.buildSaIdNumber(
      dateOfBirth,
      true,
      TestDataFactory.CITIZENSHIP_DIGIT_PERMANENT_RESIDENT,
      4999
    );

    SAIdValidator.ParsedId female = SAIdValidator.parse(femaleRefugee);
    SAIdValidator.ParsedId male = SAIdValidator.parse(malePermanentResident);

    Assert.areEqual(
      dateOfBirth,
      female.dateOfBirth,
      'Generated ID should decode back to the requested birth date'
    );
    Assert.areEqual(
      SAIdValidator.GENDER_FEMALE,
      female.gender,
      'Generated female ID should decode as female'
    );
    Assert.areEqual(
      SAIdValidator.CITIZENSHIP_REFUGEE,
      female.citizenshipStatus,
      'Generated refugee ID should decode as refugee'
    );
    Assert.areEqual(
      SAIdValidator.GENDER_MALE,
      male.gender,
      'Generated male ID (sequence 9999) should decode as male'
    );
    Assert.areEqual(
      SAIdValidator.CITIZENSHIP_PERMANENT_RESIDENT,
      male.citizenshipStatus,
      'Generated permanent-resident ID should decode as such'
    );
  }

  @IsTest
  static void bulkValidationOfFourHundredIdsCompletesWithinLimits() {
    List<String> validIds = new List<String>();
    List<String> corruptedIds = new List<String>();
    for (Integer i = 0; i < 200; i++) {
      String validId = TestDataFactory.buildSaIdNumber(
        Date.newInstance(1970, 6, 15).addDays(i),
        Math.mod(i, 2) == 0,
        Math.mod(i, 3),
        i
      );
      validIds.add(validId);
      corruptedIds.add(
        validId.left(12) +
        String.valueOf(Math.mod(Integer.valueOf(validId.right(1)) + 1, 10))
      );
    }

    Test.startTest();
    Integer validCount = 0;
    Integer invalidCount = 0;
    for (String idNumber : validIds) {
      validCount += SAIdValidator.isValid(idNumber) ? 1 : 0;
    }
    for (String idNumber : corruptedIds) {
      invalidCount += SAIdValidator.isValid(idNumber) ? 0 : 1;
    }
    Integer queriesUsed = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      200,
      validCount,
      'Every factory-generated ID should validate'
    );
    Assert.areEqual(
      200,
      invalidCount,
      'Every checksum-corrupted ID should be rejected'
    );
    Assert.areEqual(
      0,
      queriesUsed,
      'Validation must not issue SOQL, so it is safe to call in a loop'
    );
  }
}
