import { createElement } from "lwc";
import IdSearch from "c/idSearch";
import search from "@salesforce/apex/IdSearchController.search";

jest.mock(
  "@salesforce/apex/IdSearchController.search",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const VALID_ID = "8001015009087";
const INVALID_CHECKSUM_ID = "8001015009088";

const SEARCH_RESULT = {
  idNumber: VALID_ID,
  dateOfBirth: "1980-01-01",
  gender: "Male",
  citizenshipStatus: "SA Citizen",
  searchCount: 3,
  birthYear: 1980,
  isBirthdayOnHoliday: true,
  holidays: [
    {
      name: "New Year's Day",
      holidayDate: "1980-01-01",
      holidayType: "National holiday",
      isOnDateOfBirth: true
    },
    {
      name: "Human Rights Day",
      holidayDate: "1980-03-21",
      holidayType: "National holiday",
      isOnDateOfBirth: false
    },
    {
      name: "Christmas Day",
      holidayDate: "1980-12-25",
      holidayType: "National holiday",
      isOnDateOfBirth: false
    }
  ]
};

// One tick for the Apex promise, one for the re-render.
const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

function mount() {
  const element = createElement("c-id-search", { is: IdSearch });
  document.body.appendChild(element);
  return element;
}

async function typeId(element, value) {
  const input = element.shadowRoot.querySelector("lightning-input");
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
  await flushPromises();
  return input;
}

const searchButton = (element) =>
  element.shadowRoot.querySelector("lightning-button.search-button");
const validationText = (element) =>
  element.shadowRoot.querySelector(".validation-message").textContent.trim();

describe("c-id-search", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  describe("Story 1: page shell", () => {
    it("renders an ID input, a description and a Search button", () => {
      const element = mount();

      const input = element.shadowRoot.querySelector("lightning-input");
      expect(input).not.toBeNull();
      expect(input.label).toBe("SA ID Number");
      expect(
        element.shadowRoot.querySelector("section p").textContent
      ).toContain("South African ID number");
      expect(searchButton(element).label).toBe("Search");
    });

    it("starts with the Search button disabled and no results", () => {
      const element = mount();

      expect(searchButton(element).disabled).toBe(true);
      expect(element.shadowRoot.querySelector(".results")).toBeNull();
      expect(validationText(element)).toBe("");
    });
  });

  describe("Story 2: validation gates the button", () => {
    it("keeps the button disabled for a partial number without complaining while typing", async () => {
      const element = mount();

      await typeId(element, "800101");

      expect(searchButton(element).disabled).toBe(true);
      expect(validationText(element)).toBe("");
    });

    it("shows the too-short message once the visitor leaves a partial number", async () => {
      const element = mount();

      const input = await typeId(element, "800101");
      input.dispatchEvent(new CustomEvent("blur"));
      await flushPromises();

      expect(validationText(element)).toContain("13 digits");
      expect(searchButton(element).disabled).toBe(true);
    });

    it("rejects non-numeric input immediately", async () => {
      const element = mount();

      await typeId(element, "80010150O");

      expect(validationText(element)).toContain("digits only");
      expect(searchButton(element).disabled).toBe(true);
    });

    it("keeps the button disabled and shows an error for 13 digits that fail the checksum", async () => {
      const element = mount();

      await typeId(element, INVALID_CHECKSUM_ID);

      expect(searchButton(element).disabled).toBe(true);
      expect(validationText(element)).toContain(
        "not a valid South African ID number"
      );
    });

    it("enables the button and clears the error once the number is valid", async () => {
      const element = mount();

      await typeId(element, INVALID_CHECKSUM_ID);
      await typeId(element, VALID_ID);

      expect(searchButton(element).disabled).toBe(false);
      expect(validationText(element)).toBe("");
    });

    it("re-disables the button when a valid number is edited to become invalid", async () => {
      const element = mount();

      await typeId(element, VALID_ID);
      await typeId(element, INVALID_CHECKSUM_ID);

      expect(searchButton(element).disabled).toBe(true);
      expect(validationText(element)).toContain("not a valid");
    });

    it("trims whitespace pasted around the number", async () => {
      const element = mount();

      await typeId(element, `  ${VALID_ID} `);

      expect(searchButton(element).disabled).toBe(false);
    });
  });

  describe("Stories 3 & 4: search and results", () => {
    it("calls Apex with the ID number and renders decoded data plus the holiday list", async () => {
      search.mockResolvedValue(SEARCH_RESULT);
      const element = mount();

      await typeId(element, VALID_ID);
      searchButton(element).click();
      await flushPromises();

      expect(search).toHaveBeenCalledTimes(1);
      expect(search).toHaveBeenCalledWith({ idNumber: VALID_ID });
      expect(
        element.shadowRoot.querySelector(
          ".decoded-dob lightning-formatted-date-time"
        ).value
      ).toBe("1980-01-01");
      expect(
        element.shadowRoot.querySelector(".decoded-gender").textContent
      ).toBe("Male");
      expect(
        element.shadowRoot.querySelector(".decoded-citizenship").textContent
      ).toBe("SA Citizen");
      expect(
        element.shadowRoot.querySelector(".decoded-count").textContent
      ).toBe("3");
      expect(
        element.shadowRoot.querySelectorAll(".holiday-table tbody tr")
      ).toHaveLength(3);
      expect(element.shadowRoot.querySelector(".no-holiday-data")).toBeNull();
    });

    it("flags the holiday that falls on the date of birth", async () => {
      search.mockResolvedValue(SEARCH_RESULT);
      const element = mount();

      await typeId(element, VALID_ID);
      searchButton(element).click();
      await flushPromises();

      const rows = element.shadowRoot.querySelectorAll(
        ".holiday-table tbody tr"
      );
      expect(
        element.shadowRoot.querySelector(".birthday-match")
      ).not.toBeNull();
      expect(rows[0].classList.contains("birthday-row")).toBe(true);
      expect(rows[0].querySelector("lightning-badge")).not.toBeNull();
      expect(rows[1].classList.contains("birthday-row")).toBe(false);
      expect(rows[1].querySelector("lightning-badge")).toBeNull();
    });

    it("shows the not-yet-available state when no holidays are cached, while still showing decoded data", async () => {
      search.mockResolvedValue({
        ...SEARCH_RESULT,
        isBirthdayOnHoliday: false,
        holidays: []
      });
      const element = mount();

      await typeId(element, VALID_ID);
      searchButton(element).click();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector(".no-holiday-data").textContent
      ).toContain("1980");
      expect(element.shadowRoot.querySelector(".holiday-table")).toBeNull();
      expect(element.shadowRoot.querySelector(".birthday-match")).toBeNull();
      expect(
        element.shadowRoot.querySelector(".decoded-gender").textContent
      ).toBe("Male");
    });

    it("says so when the birthday is not a holiday", async () => {
      search.mockResolvedValue({
        ...SEARCH_RESULT,
        isBirthdayOnHoliday: false,
        holidays: SEARCH_RESULT.holidays.map((holiday) => ({
          ...holiday,
          isOnDateOfBirth: false
        }))
      });
      const element = mount();

      await typeId(element, VALID_ID);
      searchButton(element).click();
      await flushPromises();

      expect(element.shadowRoot.querySelector(".birthday-match")).toBeNull();
      expect(
        element.shadowRoot.querySelector(".birthday-no-match").textContent
      ).toContain("not a public holiday");
    });

    it("surfaces the server error message and renders no results when Apex rejects", async () => {
      search.mockRejectedValue({
        body: { message: "You do not have permission to run an ID search." }
      });
      jest.spyOn(console, "error").mockImplementation(() => {});
      const element = mount();

      await typeId(element, VALID_ID);
      searchButton(element).click();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector(".error-message").textContent
      ).toContain("do not have permission");
      expect(element.shadowRoot.querySelector(".results")).toBeNull();
      expect(searchButton(element).disabled).toBe(false);
    });

    it("falls back to a generic message when the error carries no body", async () => {
      search.mockRejectedValue(new Error("network"));
      jest.spyOn(console, "error").mockImplementation(() => {});
      const element = mount();

      await typeId(element, VALID_ID);
      searchButton(element).click();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector(".error-message").textContent
      ).toContain("Something went wrong");
    });

    it("disables the button while a search is in flight so a double-click cannot double-count", async () => {
      let resolveSearch;
      search.mockReturnValue(
        new Promise((resolve) => {
          resolveSearch = resolve;
        })
      );
      const element = mount();

      await typeId(element, VALID_ID);
      searchButton(element).click();
      await flushPromises();

      expect(searchButton(element).disabled).toBe(true);
      expect(
        element.shadowRoot.querySelector("lightning-spinner")
      ).not.toBeNull();

      resolveSearch(SEARCH_RESULT);
      await flushPromises();

      expect(searchButton(element).disabled).toBe(false);
      expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
      expect(search).toHaveBeenCalledTimes(1);
    });

    it("submits on Enter only when the number is valid", async () => {
      search.mockResolvedValue(SEARCH_RESULT);
      const element = mount();

      const input = await typeId(element, INVALID_CHECKSUM_ID);
      input.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter" }));
      await flushPromises();
      expect(search).not.toHaveBeenCalled();

      await typeId(element, VALID_ID);
      input.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter" }));
      await flushPromises();
      expect(search).toHaveBeenCalledTimes(1);
    });
  });
});
