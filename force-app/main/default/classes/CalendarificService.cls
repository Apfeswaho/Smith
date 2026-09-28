/**
 * @description Calendarific holidays client, called only by the System-context sync. The endpoint comes from
 *              the Calendarific_Holidays setting; this class supplies {year} and parses the reply.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
public with sharing class CalendarificService {
  public static final String ERROR_HTTP_STATUS = 'Calendarific returned HTTP {0} {1}';
  public static final String ERROR_MALFORMED_RESPONSE = 'Calendarific response could not be parsed: {0}';
  public static final String SETTING_DEVELOPER_NAME = 'Calendarific_Holidays';
  public static final String YEAR_PLACEHOLDER = 'year';

  private static final Integer HTTP_OK = 200;

  public class CalendarificException extends Exception {
  }

  public class Holiday {
    public String name;
    public Date holidayDate;
    public String primaryType;
  }

  public static List<Holiday> fetchHolidays(Integer year) {
    HttpRequest request = WebServiceSettings.buildRequest(
      SETTING_DEVELOPER_NAME,
      new Map<String, String>{ YEAR_PLACEHOLDER => String.valueOf(year) }
    );

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != HTTP_OK) {
      throw new CalendarificException(
        String.format(
          ERROR_HTTP_STATUS,
          new List<String>{
            String.valueOf(response.getStatusCode()),
            response.getStatus()
          }
        )
      );
    }
    return parseHolidays(response.getBody());
  }

  // Untyped: "date" and "type" can't be Apex member names.
  @TestVisible
  private static List<Holiday> parseHolidays(String body) {
    List<Holiday> holidays = new List<Holiday>();
    try {
      Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
        body
      );
      Map<String, Object> payload = (Map<String, Object>) root.get('response');
      for (Object rawHoliday : (List<Object>) payload.get('holidays')) {
        Map<String, Object> holidayNode = (Map<String, Object>) rawHoliday;
        Holiday holiday = new Holiday();
        holiday.name = (String) holidayNode.get('name');
        holiday.primaryType = (String) holidayNode.get('primary_type');
        holiday.holidayDate = toDate(
          (Map<String, Object>) holidayNode.get('date')
        );
        if (String.isBlank(holiday.name) || holiday.holidayDate == null) {
          throw new CalendarificException(
            'holiday entry is missing name or date'
          );
        }
        holidays.add(holiday);
      }
    } catch (Exception e) {
      throw new CalendarificException(
        String.format(
          ERROR_MALFORMED_RESPONSE,
          new List<String>{ e.getMessage() }
        )
      );
    }
    return holidays;
  }

  // "iso" carries a time and offset for some entries; the numeric parts don't.
  private static Date toDate(Map<String, Object> dateNode) {
    Map<String, Object> parts = (Map<String, Object>) dateNode.get('datetime');
    if (parts != null) {
      return Date.newInstance(
        Integer.valueOf(String.valueOf(parts.get('year'))),
        Integer.valueOf(String.valueOf(parts.get('month'))),
        Integer.valueOf(String.valueOf(parts.get('day')))
      );
    }
    return Date.valueOf(((String) dateNode.get('iso')).left(10));
  }
}
