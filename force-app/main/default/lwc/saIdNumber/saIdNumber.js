/**
 * Client-side mirror of SAIdValidator for instant feedback only; the server re-validates. Shares test vectors
 * with SAIdValidatorTest.cls.
 *
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
const THIRTEEN_DIGITS = /^\d{13}$/;
const FEMALE_SEQUENCE_MAX = 4999;
const CITIZENSHIP_BY_DIGIT = Object.freeze({
  0: "SA Citizen",
  1: "Permanent Resident",
  2: "Refugee"
});

export const GENDER_FEMALE = "Female";
export const GENDER_MALE = "Male";

/**
 * @param {string} rawIdNumber
 * @returns {{ idNumber: string, dateOfBirth: Date, gender: string, citizenshipStatus: string } | null}
 */
export function parseSaIdNumber(rawIdNumber) {
  const idNumber = (rawIdNumber ?? "").trim();
  if (!THIRTEEN_DIGITS.test(idNumber)) {
    return null;
  }
  const dateOfBirth = toDateOrNull(
    inferFullYear(Number(idNumber.slice(0, 2))),
    Number(idNumber.slice(2, 4)),
    Number(idNumber.slice(4, 6))
  );
  const citizenshipStatus = CITIZENSHIP_BY_DIGIT[idNumber.charAt(10)];
  if (!dateOfBirth || !citizenshipStatus || !hasValidLuhnChecksum(idNumber)) {
    return null;
  }
  return {
    idNumber,
    dateOfBirth,
    gender:
      Number(idNumber.slice(6, 10)) <= FEMALE_SEQUENCE_MAX
        ? GENDER_FEMALE
        : GENDER_MALE,
    citizenshipStatus
  };
}

export function isValidSaIdNumber(rawIdNumber) {
  return parseSaIdNumber(rawIdNumber) !== null;
}

// Same century rule as SAIdValidator.
function inferFullYear(twoDigitYear) {
  const currentYear = new Date().getFullYear();
  const candidate = Math.floor(currentYear / 100) * 100 + twoDigitYear;
  return candidate > currentYear ? candidate - 100 : candidate;
}

// new Date() rolls 30 Feb to 2 Mar; the round-trip check rejects it.
function toDateOrNull(year, month, day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  const candidate = new Date(year, month - 1, day);
  // The Date constructor maps years 0-99 to 1900-1999.
  candidate.setFullYear(year, month - 1, day);
  const roundTrips =
    candidate.getFullYear() === year &&
    candidate.getMonth() === month - 1 &&
    candidate.getDate() === day;
  return roundTrips ? candidate : null;
}

function hasValidLuhnChecksum(idNumber) {
  let sum = 0;
  let doubleThisDigit = false;
  for (let i = idNumber.length - 1; i >= 0; i--) {
    let digit = Number(idNumber.charAt(i));
    if (doubleThisDigit) {
      digit *= 2;
      if (digit > 9) {
        digit -= 9;
      }
    }
    sum += digit;
    doubleThisDigit = !doubleThisDigit;
  }
  return sum % 10 === 0;
}
