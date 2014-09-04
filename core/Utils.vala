//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

namespace Maya.Util {

    public int compare_events (E.CalComponent comp1, E.CalComponent comp2) {

        var date1 = Util.ical_to_date_time (comp1.get_icalcomponent ().get_dtstart ());
        var date2 = Util.ical_to_date_time (comp2.get_icalcomponent ().get_dtstart ());

        if (date1.compare (date2) != 0)
            return date1.compare(date2);

        // If they have the same date, sort them alphabetically
        E.CalComponentText summary1;
        E.CalComponentText summary2;

        comp1.get_summary (out summary1);
        comp2.get_summary (out summary2);

        if (summary1.value < summary2.value)
            return -1;
        if (summary1.value > summary2.value)
            return 1;
        return 0;
    }

    //--- Date and Time ---//


    /**
     * Converts two datetimes to one TimeType. The first contains the date,
     * its time settings are ignored. The second one contains the time itself.
     */
    public iCal.TimeType date_time_to_ical (DateTime date, DateTime? time) {

        var result = iCal.TimeType.from_day_of_year
            (date.get_day_of_year (), date.get_year ());
        result.zone = iCal.TimeZone.get_builtin_timezone (E.Cal.util_get_system_timezone_location ());

        if (time != null) {
            result.is_date = 0;
            result.hour = time.get_hour ();
            result.minute = time.get_minute ();
            result.second = time.get_second ();
        } else {
            result.is_date = 1;
            result.hour = 0;
            result.minute = 0;
            result.second = 0;
        }

        return result;
    }

    /**
     * Converts the given TimeType to a DateTime.
     */
    public DateTime ical_to_date_time (iCal.TimeType date) {

        string tzid = date.zone.get_tzid ();
        TimeZone zone = new TimeZone (tzid);

        return new DateTime (zone, date.year, date.month,
            date.day, date.hour, date.minute, date.second);
    }

    public DateTime ecal_to_date_time (E.CalComponentDateTime date) {
        TimeZone zone = new TimeZone (date.tzid);
        DateTime result = new DateTime(zone, 
                date.value.year, date.value.month, date.value.day, 
                date.value.hour, date.value.minute, date.value.second);

        return result;
    }

    public Gee.Collection<DateRange> event_date_ranges (E.CalComponent event, Util.DateRange view_range) {
        var dateranges = new Gee.LinkedList<DateRange> ();

        unowned iCal.Component comp = event.get_icalcomponent ();
        var start = ical_to_date_time (comp.get_dtstart ());
        var end = ical_to_date_time (comp.get_dtend ());

        bool allday = is_the_all_day (start, end);
        if (allday)
            end = end.add_days (-1);

        // If end is before start, switch the two
        if (end.compare (start) < 0) {
            var temp = end;
            end = start;
            start = temp;
        }

        dateranges.add (new Util.DateRange (strip_time(start), strip_time(end)));

        // Search for recursive events.
        unowned iCal.Property property = comp.get_first_property (iCal.PropertyKind.RRULE);
        if (property != null) {
            var rrule = property.get_rrule ();
            switch (rrule.freq) {
                case (iCal.RecurrenceTypeFrequency.WEEKLY):
                    generate_week_reccurence (dateranges, view_range, rrule, start, end);
                    break;
                case (iCal.RecurrenceTypeFrequency.MONTHLY):
                    generate_month_reccurence (dateranges, view_range, rrule, start, end);
                    break;
                case (iCal.RecurrenceTypeFrequency.YEARLY):
                    generate_year_reccurence (dateranges, view_range, rrule, start, end);
                    break;
                default:
                    generate_day_reccurence (dateranges, view_range, rrule, start, end);
                    break;
            }
        }

        return dateranges;
    }

    private void generate_day_reccurence (Gee.LinkedList<DateRange> dateranges, Util.DateRange view_range,
                                           iCal.RecurrenceType rrule, DateTime start, DateTime end) {
        if (rrule.until.is_null_time () == 0) {
            for (int i = 1; i <= (int)(rrule.until.day/rrule.interval); i++) {
                int n = i*rrule.interval;
                if (view_range.contains (strip_time(start).add_days (n)) || view_range.contains (strip_time(end).add_days (n)))
                    dateranges.add (new Util.DateRange (strip_time(start).add_days (n), strip_time(end).add_days (n)));
            }
        } else if (rrule.count > 0) {
            for (int i = 1; i<=rrule.count; i++) {
                int n = i*rrule.interval;
                if (view_range.contains (strip_time(start).add_days (n)) || view_range.contains (strip_time(end).add_days (n)))
                    dateranges.add (new Util.DateRange (strip_time(start).add_days (n), strip_time(end).add_days (n)));
            }
        } else {
            int i = 1;
            int n = i*rrule.interval;
            while (view_range.last.compare (strip_time(start).add_days (n)) > 0) {
                dateranges.add (new Util.DateRange (strip_time(start).add_days (n), strip_time(end).add_days (n)));
                i++;
                n = i*rrule.interval;
            }
        }
    }

    private void generate_year_reccurence (Gee.LinkedList<DateRange> dateranges, Util.DateRange view_range,
                                           iCal.RecurrenceType rrule, DateTime start, DateTime end) {
        if (rrule.until.is_null_time () == 0) {
            /*for (int i = 0; i <= rrule.until.year; i++) {
                int n = i*rrule.interval;
                if (view_range.contains (strip_time(start).add_years (n)) || view_range.contains (strip_time(end).add_years (n)))
                    dateranges.add (new Util.DateRange (strip_time(start).add_years (n), strip_time(end).add_years (n)));
            }*/
        } else if (rrule.count > 0) {
            for (int i = 1; i<=rrule.count; i++) {
                int n = i*rrule.interval;
                if (view_range.contains (strip_time(start).add_years (n)) || view_range.contains (strip_time(end).add_years (n)))
                    dateranges.add (new Util.DateRange (strip_time(start).add_years (n), strip_time(end).add_years (n)));
            }
        } else {
            int i = 1;
            int n = i*rrule.interval;
            bool is_null_time = rrule.until.is_null_time () == 1;
            var temp_start = strip_time(start).add_years (n);
            while (view_range.last.compare (temp_start) > 0) {
                if (is_null_time == false) {
                    if (temp_start.get_year () > rrule.until.year)
                        break;
                    else if (temp_start.get_year () == rrule.until.year && temp_start.get_month () > rrule.until.month)
                        break;
                    else if (temp_start.get_year () == rrule.until.year && temp_start.get_month () == rrule.until.month &&temp_start.get_day_of_month () > rrule.until.day)
                        break;
                
                }
                dateranges.add (new Util.DateRange (temp_start, strip_time(end).add_years (n)));
                i++;
                n = i*rrule.interval;
                temp_start = strip_time(start).add_years (n);
            }
        }
    }

    private void generate_month_reccurence (Gee.LinkedList<DateRange> dateranges, Util.DateRange view_range,
                                           iCal.RecurrenceType rrule, DateTime start, DateTime end) {
        for (int k = 0; k <= iCal.Size.BY_DAY; k++) {
            if (rrule.by_day[k] < iCal.Size.BY_DAY) {
                if (rrule.count > 0) {
                    for (int i = 1; i<=rrule.count; i++) {
                        int n = i*rrule.interval;
                        var start_ical_day = get_date_from_ical_day (strip_time(start).add_months (n), rrule.by_day[k]);
                        int interval = start_ical_day.get_day_of_month () - start.get_day_of_month ();
                        dateranges.add (new Util.DateRange (start_ical_day, strip_time(end).add_months (n).add_days (interval)));
                    }
                } else {
                    int i = 1;
                    int n = i*rrule.interval;
                    bool is_null_time = rrule.until.is_null_time () == 1;
                    var start_ical_day = get_date_from_ical_day (strip_time(start).add_months (n), rrule.by_day[k]);
                    while (view_range.last.compare (start_ical_day) > 0) {
                        if (is_null_time == false) {
                            if (start_ical_day.get_year () > rrule.until.year)
                                break;
                            else if (start_ical_day.get_year () == rrule.until.year && start_ical_day.get_month () > rrule.until.month)
                                break;
                            else if (start_ical_day.get_year () == rrule.until.year && start_ical_day.get_month () == rrule.until.month && start_ical_day.get_day_of_month () > rrule.until.day)
                                break;
                        
                        }

                        int interval = start_ical_day.get_day_of_month () - start.get_day_of_month ();
                        dateranges.add (new Util.DateRange (start_ical_day, strip_time(end).add_months (n).add_days (interval)));
                        i++;
                        n = i*rrule.interval;
                        start_ical_day = get_date_from_ical_day (strip_time(start).add_months (n), rrule.by_day[k]);
                    }
                }
            } else {
                break;
            }
        }

        if (rrule.by_month_day[0] < iCal.Size.BY_MONTHDAY) {
            if (rrule.count > 0) {
                for (int i = 1; i<=rrule.count; i++) {
                    int n = i*rrule.interval;
                    dateranges.add (new Util.DateRange (strip_time(start).add_months (n), strip_time(end).add_months (n)));
                }
            } else {
                int i = 1;
                int n = i*rrule.interval;
                bool is_null_time = rrule.until.is_null_time () == 1;
                var temp_start = strip_time(start).add_months (n);
                while (view_range.last.compare (temp_start) > 0) {
                    if (is_null_time == false) {
                        if (temp_start.get_year () > rrule.until.year)
                            break;
                        else if (temp_start.get_year () == rrule.until.year && temp_start.get_month () > rrule.until.month)
                            break;
                        else if (temp_start.get_year () == rrule.until.year && temp_start.get_month () == rrule.until.month && temp_start.get_day_of_month () > rrule.until.day)
                            break;
                    
                    }
                    dateranges.add (new Util.DateRange (temp_start, strip_time(end).add_months (n)));
                    i++;
                    n = i*rrule.interval;
                    temp_start = strip_time(start).add_months (n);
                }
            }
        }
    }

    private void generate_week_reccurence (Gee.LinkedList<DateRange> dateranges, Util.DateRange view_range,
                                           iCal.RecurrenceType rrule, DateTime start_, DateTime end_) {
        DateTime start = start_;
        DateTime end = end_;
        for (int k = 0; k <= iCal.Size.BY_DAY; k++) {
            if (rrule.by_day[k] > 7)
                break;
            int day_to_add = 0;
            switch (rrule.by_day[k]) {
                case 1:
                    day_to_add = 7 - start.get_day_of_week ();
                    break;
                case 2:
                    day_to_add = 1 - start.get_day_of_week ();
                    break;
                case 3:
                    day_to_add = 2 - start.get_day_of_week ();
                    break;
                case 4:
                    day_to_add = 3 - start.get_day_of_week ();
                    break;
                case 5:
                    day_to_add = 4 - start.get_day_of_week ();
                    break;
                case 6:
                    day_to_add = 5 - start.get_day_of_week ();
                    break;
                default:
                    day_to_add = 6 - start.get_day_of_week ();
                    break;
            }
            if (start.add_days (day_to_add).get_month () < start.get_month ())
                day_to_add = day_to_add + 7;

            start = start.add_days (day_to_add);
            end = end.add_days (day_to_add);

            if (rrule.count > 0) {
                for (int i = 1; i<=rrule.count; i++) {
                    int n = i*rrule.interval*7;
                    if (view_range.contains (strip_time(start).add_days (n)) || view_range.contains (strip_time(end).add_days (n)))
                        dateranges.add (new Util.DateRange (strip_time(start).add_days (n), strip_time(end).add_days (n)));
                }
            } else {
                int i = 1;
                int n = i*rrule.interval*7;
                bool is_null_time = rrule.until.is_null_time () == 1;
                var temp_start = strip_time(start).add_days (n);
                while (view_range.last.compare (temp_start) > 0) {
                    if (is_null_time == false) {
                        if (temp_start.get_year () > rrule.until.year)
                            break;
                        else if (temp_start.get_year () == rrule.until.year && temp_start.get_month () > rrule.until.month)
                            break;
                        else if (temp_start.get_year () == rrule.until.year && temp_start.get_month () == rrule.until.month &&temp_start.get_day_of_month () > rrule.until.day)
                            break;
                    
                    }
                    dateranges.add (new Util.DateRange (temp_start, strip_time(end).add_days (n)));
                    i++;
                    n = i*rrule.interval*7;
                    temp_start = strip_time(start).add_days (n);
                }
            }
        }
    }

    public bool is_multiday_event (E.CalComponent event) {
        E.CalComponentDateTime dt_start;
        event.get_dtstart (out dt_start);

        E.CalComponentDateTime dt_end;
        event.get_dtend (out dt_end);

        var start = ecal_to_date_time (dt_start);
        var end = ecal_to_date_time (dt_end);

        bool allday = is_the_all_day (start, end);
        if (allday)
            end = end.add_days (-1);

        // If end is before start, switch the two
        if (end.compare (start) < 0) {
            var temp = end;
            end = start;
            start = temp;
        }
        var event_range = new Util.DateRange (strip_time(start), strip_time(end));
        return event_range.to_list() .size > 1;
    }

    /**
     * Say if an event lasts all day.
     */
    public bool is_the_all_day (DateTime dtstart, DateTime dtend) {
        if ((dtend.get_hour() == dtend.get_minute()) && (dtstart.get_hour() == dtend.get_hour()) && (dtstart.get_hour() == dtstart.get_minute()) && (dtend.get_hour() == 0)) {
            return true;
        }
        else {
            return false;
        }
    }
    
    public DateTime get_date_from_ical_day (DateTime date, short day) {
        int day_to_add = 0;
        switch (iCal.RecurrenceType.day_day_of_week (day)) {
            case iCal.RecurrenceTypeWeekday.SUNDAY:
                day_to_add = 7 - date.get_day_of_week ();
                break;
            case iCal.RecurrenceTypeWeekday.MONDAY:
                day_to_add = 1 - date.get_day_of_week ();
                break;
            case iCal.RecurrenceTypeWeekday.TUESDAY:
                day_to_add = 2 - date.get_day_of_week ();
                break;
            case iCal.RecurrenceTypeWeekday.WEDNESDAY:
                day_to_add = 3 - date.get_day_of_week ();
                break;
            case iCal.RecurrenceTypeWeekday.THURSDAY:
                day_to_add = 4 - date.get_day_of_week ();
                break;
            case iCal.RecurrenceTypeWeekday.FRIDAY:
                day_to_add = 5 - date.get_day_of_week ();
                break;
            default:
                day_to_add = 6 - date.get_day_of_week ();
                break;
        }
        if (date.add_days (day_to_add).get_month () < date.get_month ())
            day_to_add = day_to_add + 7;

        if (date.add_days (day_to_add).get_month () > date.get_month ())
            day_to_add = day_to_add - 7;

        switch (iCal.RecurrenceType.day_position (day)) {
            case 1:
                int n = (int)GLib.Math.trunc ((date.get_day_of_month () + day_to_add) / 7);
                return date.add_days (day_to_add - n * 7);
            case 2:
                int n = (int)GLib.Math.trunc ((date.get_day_of_month () + day_to_add - 7) / 7);
                return date.add_days (day_to_add - n * 7);
            case 3:
                int n = (int)GLib.Math.trunc ((date.get_day_of_month () + day_to_add - 14) / 7);
                return date.add_days (day_to_add - n * 7);
            case 4:
                int n = (int)GLib.Math.trunc ((date.get_day_of_month () + day_to_add - 21) / 7);
                return date.add_days (day_to_add - n * 7);
            default:
                int n = (int)GLib.Math.trunc ((date.get_day_of_month () + day_to_add - 28) / 7);
                return date.add_days (day_to_add - n * 7);
        }
    }

    public DateTime get_start_of_month (owned DateTime? date = null) {

        if (date==null)
            date = new DateTime.now_local();

        return new DateTime.local (date.get_year(), date.get_month(), 1, 0, 0, 0);
    }

    public DateTime strip_time (DateTime datetime) {
        int y,m,d;
        datetime.get_ymd (out y, out m, out d);
        return new DateTime.local (y, m, d, 0, 0, 0);
    }

    /* Create a map interleaving DateRanges dr1 and dr2 */
    public Gee.Map<DateTime, DateTime> zip_date_ranges (DateRange dr1, DateRange dr2)
        requires (dr1.days == dr2.days) {

        var map = new Gee.TreeMap<DateTime, DateTime>(
            (GLib.CompareDataFunc<E.CalComponent>?) DateTime.compare,
            (Gee.EqualDataFunc<GLib.DateTime>?) datetime_equal_func);

        var i1 = dr1.iterator();
        var i2 = dr2.iterator();

        while (i1.next() && i2.next()) {
            map.set (i1.get(), i2.get());
        }

        return map;
    }

    /* Iterator of DateRange objects */
    public class DateIterator : Object, Gee.Traversable<DateTime>, Gee.Iterator<DateTime> {

        DateTime current;
        DateRange range;

        public bool valid { get {return true;} }
        public bool read_only { get {return false;} }

        public DateIterator (DateRange range) {
            this.range = range;
            this.current = range.first.add_days (-1);
        }

        public bool @foreach (Gee.ForallFunc<DateTime> f) {
            var element = range.first;

            while (element.compare (range.last) < 0) {
                if (f (element) == false) {
                    return false;
                }

                element = element.add_days (1);
            }

            return true;
        }

        public bool next () {
            if (! has_next ())
                return false;
            current = this.current.add_days (1);
            return true;
        }

        public bool has_next() {
            return current.compare(range.last) < 0;
        }

        public bool first () {
            current = range.first;
            return true;
        }

        public new DateTime get () {
            return current;
        }

        public void remove() {
            assert_not_reached();
        }
    }

    /* Represents date range from 'first' to 'last' inclusive */
    public class DateRange : Object, Gee.Traversable<DateTime>, Gee.Iterable<DateTime> {

        public DateTime first { get; private set; }
        public DateTime last { get; private set; }

        public bool @foreach (Gee.ForallFunc<DateTime> f) {
            foreach (var date in this) {
                if (f (date) == false) {
                    return false;
                }
            }

            return true;
        }

        public int64 days {
            get { return last.difference (first) / GLib.TimeSpan.DAY; }
        }

        public DateRange (DateTime first, DateTime last) {
            assert (first.compare(last)<=0);
            this.first = first;
            this.last = last;
        }

        public DateRange.copy (DateRange date_range) {
            this (date_range.first, date_range.last);
        }

        public bool equals (DateRange other) {
            return (first==other.first && last==other.last);
        }

        public Type element_type {
            get { return typeof(DateTime); }
        }

        public Gee.Iterator<DateTime> iterator () {
            return new DateIterator (this);
        }

        public bool contains (DateTime time) {
            return (first.compare (time) < 1) && (last.compare (time) > -1);
        }

        public Gee.SortedSet<DateTime> to_set() {

            var @set = new Gee.TreeSet<DateTime> ((GLib.CompareDataFunc<GLib.DateTime>?) DateTime.compare);

            foreach (var date in this)
                set.add (date);

            return @set;
        }

        public Gee.List<DateTime> to_list() {

            var list = new Gee.ArrayList<DateTime> ((Gee.EqualDataFunc<GLib.DateTime>?) datetime_equal_func);

            foreach (var date in this)
                list.add (date);

            return list;
        }
    }

    //--- Gee Utility Functions ---//

    /* Interleaves the values of two collections into a Map */
    public void zip<F, G> (Gee.Iterable<F> iterable1, Gee.Iterable<G> iterable2, ref Gee.Map<F, G> map) {

        var i1 = iterable1.iterator();
        var i2 = iterable2.iterator();

        while (i1.next() && i2.next())
            map.set (i1, i2);
    }

    /* Constructs a new set with keys equal to the values of keymap */
    public void remap<K, V> (Gee.Map<K, K> keymap, Gee.Map<K, V> valmap, ref Gee.Map<K, V> remap) {

        foreach (K key in valmap) {

            var k = keymap [key];
            var v = valmap [key];

            remap.set (k, v);
        }
    }

    /* Computes hash value for string */
    public uint string_hash_func (string key) {
        return key.hash();
    }

    /* Computes hash value for DateTime */
    public uint datetime_hash_func (DateTime key) {
        return key.hash();
    }

    /* Computes hash value for E.CalComponent */
    public uint calcomponent_hash_func (E.CalComponent key) {
        string uid;
        key.get_uid (out uid);
        return str_hash (uid);
    }

    /* Computes hash value for E.Source */
    public uint source_hash_func (E.Source key) {
        return str_hash (key.dup_uid());
    }

    /* Returns true if 'a' and 'b' are the same string */
    public bool string_equal_func (string a, string b) {
        return a == b;
    }

    /* Returns true if 'a' and 'b' are the same GLib.DateTime */
    public bool datetime_equal_func (DateTime a, DateTime b) {
        return a.equal (b);
    }

    /* Returns true if 'a' and 'b' are the same E.CalComponent */
    public bool calcomponent_equal_func (E.CalComponent a, E.CalComponent b) {
        string uid_a, uid_b;
        a.get_uid (out uid_a);
        b.get_uid (out uid_b);
        return uid_a == uid_b;
    }

    /* Returns true if 'a' and 'b' are the same E.Source */
    public bool source_equal_func (E.Source a, E.Source b) {
        return a.dup_uid() == b.dup_uid();
    }

    //--- TreeModel Utility Functions ---//

    public Gtk.TreePath? find_treemodel_object<T> (Gtk.TreeModel model, int column, T object, EqualFunc<T>? eqfunc=null) {

        Gtk.TreePath? path = null;

        model.foreach( (m, p, iter) => {

            Value gvalue;
            model.get_value (iter, column, out gvalue);

            T ovalue = gvalue.get_object();

            if (   (eqfunc == null && ovalue == object)
                || (eqfunc != null && eqfunc(ovalue, object))) {
                path = p;
                return true;
            }

            return false;
        });

        return path;
    }

    //--- Gtk Miscellaneous ---//

    public class Css {

        private static Gtk.CssProvider? _css_provider;

        // Retrieve global css provider
        public static Gtk.CssProvider get_css_provider () {

            if (_css_provider == null) {
                _css_provider = new Gtk.CssProvider ();
                try {
                    _css_provider.load_from_path (Build.PKGDATADIR + "/style/default.css");
                } catch (Error e) {
                    warning ("Could not add css provider. Some widgets will not look as intended. %s", e.message);
                }
            }

            return _css_provider;
        }
    }

    public Gtk.Widget set_margins (Gtk.Widget widget, int top, int right, int bottom, int left) {
        widget.margin_top = top;
        widget.margin_right = right;
        widget.margin_bottom = bottom;
        widget.margin_left = left;

        return widget;
    }

    public Gtk.Alignment set_paddings (Gtk.Widget widget, int top, int right, int bottom, int left) {
        var alignment = new Gtk.Alignment (0.0f, 0.0f, 1.0f, 1.0f);
        alignment.top_padding = top;
        alignment.right_padding = right;
        alignment.bottom_padding = bottom;
        alignment.left_padding = left;

        alignment.add (widget);
        return alignment;
    }


    //--- ical Exportation ---//


    /**
     * Export all the selected calendars to a temporary ical file
     * TODO : The code can surely be optimised, it is just a first try.
     */

    public void save_temp_selected_calendars (){
        //TODO:Create the code !
    }

    public string get_hexa_color (Gdk.RGBA color) {
        return "#%02X%02X%02X".printf ((uint)(color.red*255), (uint)(color.green*255), (uint)(color.blue*255));
    }

}