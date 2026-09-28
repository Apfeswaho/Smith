/**
 * @description Calendarific mock: records requests and returns realistic payloads.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
@IsTest
public class CalendarificCalloutMock implements HttpCalloutMock {
  public List<HttpRequest> requests = new List<HttpRequest>();

  private final Integer statusCode;
  private final String status;
  private final String body;

  public CalendarificCalloutMock(
    Integer statusCode,
    String status,
    String body
  ) {
    this.statusCode = statusCode;
    this.status = status;
    this.body = body;
  }

  public static CalendarificCalloutMock success(
    Integer year,
    Integer holidayCount
  ) {
    return new CalendarificCalloutMock(
      200,
      'OK',
      successBody(year, holidayCount)
    );
  }

  public HttpResponse respond(HttpRequest request) {
    requests.add(request);
    HttpResponse response = new HttpResponse();
    response.setStatusCode(statusCode);
    response.setStatus(status);
    response.setHeader('Content-Type', 'application/json');
    response.setBody(body);
    return response;
  }

  // Real response shape, including the iso-with-offset date variant.
  public static String successBody(Integer year, Integer holidayCount) {
    List<Object> holidays = new List<Object>();
    for (Integer i = 0; i < holidayCount; i++) {
      Date holidayDate = Date.newInstance(year, 1, 1).addDays(i * 30);
      holidays.add(
        new Map<String, Object>{
          'name' => 'Sample Holiday ' + i,
          'description' => 'Sample description ' + i,
          'country' => new Map<String, Object>{
            'id' => 'za',
            'name' => 'South Africa'
          },
          'date' => new Map<String, Object>{
            'iso' => String.valueOf(holidayDate) + 'T00:00:00+02:00',
            'datetime' => new Map<String, Object>{
              'year' => holidayDate.year(),
              'month' => holidayDate.month(),
              'day' => holidayDate.day()
            }
          },
          'type' => new List<String>{ 'National holiday' },
          'primary_type' => 'National holiday',
          'locations' => 'All',
          'states' => 'All'
        }
      );
    }
    return JSON.serialize(
      new Map<String, Object>{
        'meta' => new Map<String, Object>{ 'code' => 200 },
        'response' => new Map<String, Object>{ 'holidays' => holidays }
      }
    );
  }
}
