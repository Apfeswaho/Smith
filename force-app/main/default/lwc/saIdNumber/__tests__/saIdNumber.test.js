/**
 * Vectors shared with SAIdValidatorTest.cls - change both together.
 */
import {
  parseSaIdNumber,
  isValidSaIdNumber,
  GENDER_FEMALE,
  GENDER_MALE
} from "c/saIdNumber";

const VALID_MALE_CITIZEN_1980 = "8001015009087";
const VALID_FEMALE_CITIZEN_1990 = "9002200472089";
const VALID_MALE_PERMANENT_RESIDENT_1985 = "8512315123188";
const VALID_FEMALE_REFUGEE_2001 = "0107152345289";
const VALID_FEMALE_LEAP_DAY_2000 = "0002290001086";
const VALID_FEMALE_SEQUENCE_4999 = "7506154999089";
const VALID_MALE_SEQUENCE_5000 = "7506155000085";
const INVALID_CHECKSUM_OFF_BY_ONE = "8001015009088";
const INVALID_MONTH_13_CHECKSUM_OK = "9913015800084";
const INVALID_FEB_30_CHECKSUM_OK = "9902305800086";
const INVALID_FEB_29_NON_LEAP_CHECKSUM_OK = "9902290001088";
const INVALID_DAY_00_CHECKSUM_OK = "8001005009089";
const INVALID_CITIZENSHIP_3_CHECKSUM_OK = "8001015009384";

const localDate = (year, month, day) => {
  const date = new Date(year, month - 1, day);
  date.setFullYear(year, month - 1, day);
  return date;
};

describe("c-sa-id-number parseSaIdNumber", () => {
  it("decodes the published example to a male SA citizen born 1 Jan 1980", () => {
    const parsed = parseSaIdNumber(VALID_MALE_CITIZEN_1980);

    expect(parsed).not.toBeNull();
    expect(parsed.idNumber).toBe(VALID_MALE_CITIZEN_1980);
    expect(parsed.dateOfBirth).toEqual(localDate(1980, 1, 1));
    expect(parsed.gender).toBe(GENDER_MALE);
    expect(parsed.citizenshipStatus).toBe("SA Citizen");
  });

  it("decodes every citizenship digit", () => {
    expect(parseSaIdNumber(VALID_FEMALE_CITIZEN_1990).citizenshipStatus).toBe(
      "SA Citizen"
    );
    expect(
      parseSaIdNumber(VALID_MALE_PERMANENT_RESIDENT_1985).citizenshipStatus
    ).toBe("Permanent Resident");
    expect(parseSaIdNumber(VALID_FEMALE_REFUGEE_2001).citizenshipStatus).toBe(
      "Refugee"
    );
  });

  it("splits gender between sequence 4999 and 5000", () => {
    expect(parseSaIdNumber(VALID_FEMALE_SEQUENCE_4999).gender).toBe(
      GENDER_FEMALE
    );
    expect(parseSaIdNumber(VALID_MALE_SEQUENCE_5000).gender).toBe(GENDER_MALE);
  });

  it("infers the 2000s for recent two-digit years, including a leap day", () => {
    expect(parseSaIdNumber(VALID_FEMALE_LEAP_DAY_2000).dateOfBirth).toEqual(
      localDate(2000, 2, 29)
    );
    expect(parseSaIdNumber(VALID_FEMALE_REFUGEE_2001).dateOfBirth).toEqual(
      localDate(2001, 7, 15)
    );
  });

  it("never places the birth date in the future when inferring the century", () => {
    const currentYear = new Date().getFullYear();
    const yy = (n) => String(n % 100).padStart(2, "0");
    const withChecksum = (firstTwelve) =>
      firstTwelve + luhnCheckDigit(firstTwelve);
    const thisYear = withChecksum(`${yy(currentYear)}0304500908`);
    const nextYearDigits = withChecksum(`${yy(currentYear + 1)}0304500908`);

    expect(parseSaIdNumber(thisYear).dateOfBirth.getFullYear()).toBe(
      currentYear
    );
    expect(parseSaIdNumber(nextYearDigits).dateOfBirth.getFullYear()).toBe(
      currentYear - 99
    );
  });

  it("trims surrounding whitespace before validating", () => {
    expect(parseSaIdNumber(`  ${VALID_MALE_CITIZEN_1980}\n`).idNumber).toBe(
      VALID_MALE_CITIZEN_1980
    );
  });
});

describe("c-sa-id-number isValidSaIdNumber", () => {
  it("rejects a checksum that is off by one", () => {
    expect(isValidSaIdNumber(VALID_MALE_CITIZEN_1980)).toBe(true);
    expect(isValidSaIdNumber(INVALID_CHECKSUM_OFF_BY_ONE)).toBe(false);
  });

  it("rejects impossible calendar dates even when the checksum passes", () => {
    expect(isValidSaIdNumber(INVALID_MONTH_13_CHECKSUM_OK)).toBe(false);
    expect(isValidSaIdNumber(INVALID_FEB_30_CHECKSUM_OK)).toBe(false);
    expect(isValidSaIdNumber(INVALID_FEB_29_NON_LEAP_CHECKSUM_OK)).toBe(false);
    expect(isValidSaIdNumber(INVALID_DAY_00_CHECKSUM_OK)).toBe(false);
  });

  it("rejects an undefined citizenship digit even when the checksum passes", () => {
    expect(isValidSaIdNumber(INVALID_CITIZENSHIP_3_CHECKSUM_OK)).toBe(false);
  });

  it("rejects wrong length and non-numeric input without throwing", () => {
    expect(isValidSaIdNumber(null)).toBe(false);
    expect(isValidSaIdNumber(undefined)).toBe(false);
    expect(isValidSaIdNumber("")).toBe(false);
    expect(isValidSaIdNumber("   ")).toBe(false);
    expect(isValidSaIdNumber("800101500908")).toBe(false);
    expect(isValidSaIdNumber("80010150090871")).toBe(false);
    expect(isValidSaIdNumber("80010150O9087")).toBe(false);
    expect(isValidSaIdNumber("8001-015-00908")).toBe(false);
  });
});

// Mirrors TestDataFactory.luhnCheckDigit.
function luhnCheckDigit(firstTwelve) {
  let sum = 0;
  let doubleThisDigit = true;
  for (let i = firstTwelve.length - 1; i >= 0; i--) {
    let digit = Number(firstTwelve.charAt(i));
    if (doubleThisDigit) {
      digit *= 2;
      if (digit > 9) {
        digit -= 9;
      }
    }
    sum += digit;
    doubleThisDigit = !doubleThisDigit;
  }
  return (10 - (sum % 10)) % 10;
}
