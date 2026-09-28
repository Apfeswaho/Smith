/**
 * Public SA ID search page. Client-side validation only gates the button; the server re-validates.
 *
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
import { LightningElement } from "lwc";
import search from "@salesforce/apex/IdSearchController.search";
import { isValidSaIdNumber } from "c/saIdNumber";

const ID_LENGTH = 13;
const DIGITS_ONLY = /^\d*$/;
const ERROR_NON_NUMERIC = "An ID number contains digits only.";
const ERROR_TOO_SHORT = "An ID number is 13 digits long.";
const ERROR_INVALID =
  "This is not a valid South African ID number. Check the digits and try again.";
const ERROR_UNEXPECTED =
  "Something went wrong while searching. Please try again.";

export default class IdSearch extends LightningElement {
  idNumber = "";
  result;
  errorMessage;
  isSearching = false;
  hasLeftInput = false;

  get isIdValid() {
    return isValidSaIdNumber(this.idNumber);
  }

  get isSearchDisabled() {
    return !this.isIdValid || this.isSearching;
  }

  // Stays quiet while a plausible prefix is still being typed.
  get validationMessage() {
    if (this.idNumber.length === 0) {
      return "";
    }
    if (!DIGITS_ONLY.test(this.idNumber)) {
      return ERROR_NON_NUMERIC;
    }
    if (this.idNumber.length < ID_LENGTH) {
      return this.hasLeftInput ? ERROR_TOO_SHORT : "";
    }
    return this.isIdValid ? "" : ERROR_INVALID;
  }

  get hasHolidays() {
    return Boolean(this.result?.holidays?.length);
  }

  get holidayRows() {
    return (this.result?.holidays ?? []).map((holiday) => ({
      ...holiday,
      key: `${holiday.holidayDate}-${holiday.name}`,
      rowClass: holiday.isOnDateOfBirth
        ? "slds-hint-parent birthday-row"
        : "slds-hint-parent"
    }));
  }

  handleIdChange(event) {
    this.idNumber = (event.target.value ?? "").trim();
    this.errorMessage = undefined;
  }

  handleIdBlur() {
    this.hasLeftInput = true;
  }

  handleKeyUp(event) {
    if (event.key === "Enter" && !this.isSearchDisabled) {
      this.handleSearch();
    }
  }

  async handleSearch() {
    if (this.isSearchDisabled) {
      return;
    }
    this.isSearching = true;
    this.errorMessage = undefined;
    this.result = undefined;
    try {
      this.result = await search({ idNumber: this.idNumber });
    } catch (error) {
      // Server messages are user-facing; anything else is a transport failure.
      this.errorMessage = error?.body?.message || ERROR_UNEXPECTED;
      console.error("IdSearchController.search failed", JSON.stringify(error));
    } finally {
      this.isSearching = false;
    }
  }
}
