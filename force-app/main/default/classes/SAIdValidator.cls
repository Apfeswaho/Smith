/**
 * @description Validates and decodes SA ID numbers (YYMMDD SSSS C A Z). Mirrored in c/saIdNumber for UI feedback
 *              only; both share the same test vectors.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
public with sharing class SAIdValidator {
  public static final String ERROR_INVALID_ID = 'The value entered is not a valid South African ID number.';
  public static final String GENDER_FEMALE = 'Female';
  public static final String GENDER_MALE = 'Male';
  public static final String CITIZENSHIP_CITIZEN = 'SA Citizen';
  public static final String CITIZENSHIP_PERMANENT_RESIDENT = 'Permanent Resident';
  public static final String CITIZENSHIP_REFUGEE = 'Refugee';

  private static final Pattern THIRTEEN_DIGITS = Pattern.compile('^[0-9]{13}$');
  private static final Integer FEMALE_SEQUENCE_MAX = 4999;
  private static final Map<String, String> CITIZENSHIP_BY_DIGIT = new Map<String, String>{
    '0' => CITIZENSHIP_CITIZEN,
    '1' => CITIZENSHIP_PERMANENT_RESIDENT,
    '2' => CITIZENSHIP_REFUGEE
  };

  public class InvalidIdException extends Exception {
  }

  public class ParsedId {
    @AuraEnabled
    public String idNumber;
    @AuraEnabled
    public Date dateOfBirth;
    @AuraEnabled
    public String gender;
    @AuraEnabled
    public String citizenshipStatus;
  }

  public static Boolean isValid(String idNumber) {
    return parseOrNull(idNumber) != null;
  }

  public static ParsedId parse(String idNumber) {
    ParsedId parsed = parseOrNull(idNumber);
    if (parsed == null) {
      throw new InvalidIdException(ERROR_INVALID_ID);
    }
    return parsed;
  }

  private static ParsedId parseOrNull(String rawIdNumber) {
    String idNumber = rawIdNumber?.trim();
    if (idNumber == null || !THIRTEEN_DIGITS.matcher(idNumber).matches()) {
      return null;
    }
    Date dateOfBirth = toDateOrNull(
      inferFullYear(Integer.valueOf(idNumber.substring(0, 2))),
      Integer.valueOf(idNumber.substring(2, 4)),
      Integer.valueOf(idNumber.substring(4, 6))
    );
    String citizenshipStatus = CITIZENSHIP_BY_DIGIT.get(
      idNumber.substring(10, 11)
    );
    if (
      dateOfBirth == null ||
      citizenshipStatus == null ||
      !hasValidLuhnChecksum(idNumber)
    ) {
      return null;
    }

    ParsedId parsed = new ParsedId();
    parsed.idNumber = idNumber;
    parsed.dateOfBirth = dateOfBirth;
    parsed.gender = Integer.valueOf(idNumber.substring(6, 10)) <=
      FEMALE_SEQUENCE_MAX
      ? GENDER_FEMALE
      : GENDER_MALE;
    parsed.citizenshipStatus = citizenshipStatus;
    return parsed;
  }

  // The ID has no century: use the latest one that doesn't put the birth date in the future.
  private static Integer inferFullYear(Integer twoDigitYear) {
    Integer currentYear = Date.today().year();
    Integer candidate = (currentYear / 100) * 100 + twoDigitYear;
    return candidate > currentYear ? candidate - 100 : candidate;
  }

  // Date.newInstance() rolls 30 Feb to 2 Mar instead of failing; the round-trip check rejects it.
  private static Date toDateOrNull(Integer year, Integer month, Integer day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    Date candidate = Date.newInstance(year, month, day);
    return (candidate.month() == month &&
      candidate.day() == day)
      ? candidate
      : null;
  }

  private static Boolean hasValidLuhnChecksum(String idNumber) {
    Integer sum = 0;
    Boolean doubleThisDigit = false;
    for (Integer i = idNumber.length() - 1; i >= 0; i--) {
      Integer digit = Integer.valueOf(idNumber.substring(i, i + 1));
      if (doubleThisDigit) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }
      sum += digit;
      doubleThisDigit = !doubleThisDigit;
    }
    return Math.mod(sum, 10) == 0;
  }
}
