WARNING: This is a development server. Do not use it in a production setting. Use a production WSGI or ASGI server instead.
For more information on production servers see: https://docs.djangoproject.com/en/5.2/howto/deployment/
Daily trip scheduler failed
Traceback (most recent call last):
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 105, in _execute
    return self.cursor.execute(sql, params)
           ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/mysql/base.py", line 76, in execute
    return self.cursor.execute(query, args)
           ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/cursors.py", line 153, in execute
    result = self._query(query)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/cursors.py", line 322, in _query
    conn.query(q)
    ~~~~~~~~~~^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 563, in query
    self._affected_rows = self._read_query_result(unbuffered=unbuffered)
                          ~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 825, in _read_query_result
    result.read()
    ~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 1199, in read
    first_packet = self.connection._read_packet()
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 775, in _read_packet
    packet.raise_for_error()
    ~~~~~~~~~~~~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/protocol.py", line 219, in raise_for_error
    err.raise_mysql_exception(self._data)
    ~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/err.py", line 150, in raise_mysql_exception
    raise errorclass(errno, errval)
pymysql.err.OperationalError: (1054, "Unknown column 'app_dailytriphouseholdcollection.carried_to_assignment_id' in 'field list'")

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/services/daily_trip_scheduler.py", line 82, in run_daily_trip_job
    result = run_for_date(target_date=target_date, force=force)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/management/commands/generate_daily_trips.py", line 105, in run_for_date
    assignment = DailyTripAssignment.objects.create(
        trip_plan_id=plan,
        trip_date=today,
        **defaults,
    )
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/manager.py", line 87, in manager_method
    return getattr(self.get_queryset(), name)(*args, **kwargs)
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 665, in create
    obj.save(force_insert=True, using=self.db)
    ~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/models/core_modules/daily_operations/daily_trip_assignment.py", line 299, in save
    super().save(*args, **kwargs)
    ~~~~~~~~~~~~^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/base.py", line 902, in save
    self.save_base(
    ~~~~~~~~~~~~~~^
        using=using,
        ^^^^^^^^^^^^
    ...<2 lines>...
        update_fields=update_fields,
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    )
    ^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/base.py", line 1023, in save_base
    post_save.send(
    ~~~~~~~~~~~~~~^
        sender=origin,
        ^^^^^^^^^^^^^^
    ...<4 lines>...
        using=using,
        ^^^^^^^^^^^^
    )
    ^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/dispatch/dispatcher.py", line 189, in send
    response = receiver(signal=self, sender=sender, **named)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/signals/trip_plan_signals.py", line 165, in copy_trip_plan_stops_to_daily_assignment
    sync_daily_assignment_stops_from_plan(instance)
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/signals/trip_plan_signals.py", line 156, in sync_daily_assignment_stops_from_plan
    added += _create_daily_household_collections(assignment, stop)
             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/signals/trip_plan_signals.py", line 84, in _create_daily_household_collections
    _, created = DailyTripHouseholdCollection.objects.get_or_create(
                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^
        trip_assignment_id=assignment,
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    ...<6 lines>...
        },
        ^^
    )
    ^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/manager.py", line 87, in manager_method
    return getattr(self.get_queryset(), name)(*args, **kwargs)
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 948, in get_or_create
    return self.get(**kwargs), False
           ~~~~~~~~^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 631, in get
    num = len(clone)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 368, in __len__
    self._fetch_all()
    ~~~~~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 1954, in _fetch_all
    self._result_cache = list(self._iterable_class(self))
                         ~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 93, in __iter__
    results = compiler.execute_sql(
        chunked_fetch=self.chunked_fetch, chunk_size=self.chunk_size
    )
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/sql/compiler.py", line 1623, in execute_sql
    cursor.execute(sql, params)
    ~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 122, in execute
    return super().execute(sql, params)
           ~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 79, in execute
    return self._execute_with_wrappers(
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~^
        sql, params, many=False, executor=self._execute
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    )
    ^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 92, in _execute_with_wrappers
    return executor(sql, params, many, context)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 100, in _execute
    with self.db.wrap_database_errors:
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/utils.py", line 91, in __exit__
    raise dj_exc_value.with_traceback(traceback) from exc_value
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 105, in _execute
    return self.cursor.execute(sql, params)
           ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/mysql/base.py", line 76, in execute
    return self.cursor.execute(query, args)
           ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/cursors.py", line 153, in execute
    result = self._query(query)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/cursors.py", line 322, in _query
    conn.query(q)
    ~~~~~~~~~~^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 563, in query
    self._affected_rows = self._read_query_result(unbuffered=unbuffered)
                          ~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 825, in _read_query_result
    result.read()
    ~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 1199, in read
    first_packet = self.connection._read_packet()
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 775, in _read_packet
    packet.raise_for_error()
    ~~~~~~~~~~~~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/protocol.py", line 219, in raise_for_error
    err.raise_mysql_exception(self._data)
    ~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/err.py", line 150, in raise_mysql_exception
    raise errorclass(errno, errval)
django.db.utils.OperationalError: (1054, "Unknown column 'app_dailytriphouseholdcollection.carried_to_assignment_id' in 'field list'")
Scheduled daily trip generation failed
Traceback (most recent call last):
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 105, in _execute
    return self.cursor.execute(sql, params)
           ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/mysql/base.py", line 76, in execute
    return self.cursor.execute(query, args)
           ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/cursors.py", line 153, in execute
    result = self._query(query)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/cursors.py", line 322, in _query
    conn.query(q)
    ~~~~~~~~~~^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 563, in query
    self._affected_rows = self._read_query_result(unbuffered=unbuffered)
                          ~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 825, in _read_query_result
    result.read()
    ~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 1199, in read
    first_packet = self.connection._read_packet()
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 775, in _read_packet
    packet.raise_for_error()
    ~~~~~~~~~~~~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/protocol.py", line 219, in raise_for_error
    err.raise_mysql_exception(self._data)
    ~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/err.py", line 150, in raise_mysql_exception
    raise errorclass(errno, errval)
pymysql.err.OperationalError: (1054, "Unknown column 'app_dailytriphouseholdcollection.carried_to_assignment_id' in 'field list'")

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/services/daily_trip_scheduler.py", line 134, in _scheduler_loop
    run_daily_trip_job(target_date=now.date())
    ~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/services/daily_trip_scheduler.py", line 82, in run_daily_trip_job
    result = run_for_date(target_date=target_date, force=force)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/management/commands/generate_daily_trips.py", line 105, in run_for_date
    assignment = DailyTripAssignment.objects.create(
        trip_plan_id=plan,
        trip_date=today,
        **defaults,
    )
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/manager.py", line 87, in manager_method
    return getattr(self.get_queryset(), name)(*args, **kwargs)
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 665, in create
    obj.save(force_insert=True, using=self.db)
    ~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/models/core_modules/daily_operations/daily_trip_assignment.py", line 299, in save
    super().save(*args, **kwargs)
    ~~~~~~~~~~~~^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/base.py", line 902, in save
    self.save_base(
    ~~~~~~~~~~~~~~^
        using=using,
        ^^^^^^^^^^^^
    ...<2 lines>...
        update_fields=update_fields,
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    )
    ^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/base.py", line 1023, in save_base
    post_save.send(
    ~~~~~~~~~~~~~~^
        sender=origin,
        ^^^^^^^^^^^^^^
    ...<4 lines>...
        using=using,
        ^^^^^^^^^^^^
    )
    ^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/dispatch/dispatcher.py", line 189, in send
    response = receiver(signal=self, sender=sender, **named)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/signals/trip_plan_signals.py", line 165, in copy_trip_plan_stops_to_daily_assignment
    sync_daily_assignment_stops_from_plan(instance)
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/signals/trip_plan_signals.py", line 156, in sync_daily_assignment_stops_from_plan
    added += _create_daily_household_collections(assignment, stop)
             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/app/signals/trip_plan_signals.py", line 84, in _create_daily_household_collections
    _, created = DailyTripHouseholdCollection.objects.get_or_create(
                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^
        trip_assignment_id=assignment,
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    ...<6 lines>...
        },
        ^^
    )
    ^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/manager.py", line 87, in manager_method
    return getattr(self.get_queryset(), name)(*args, **kwargs)
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 948, in get_or_create
    return self.get(**kwargs), False
           ~~~~~~~~^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 631, in get
    num = len(clone)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 368, in __len__
    self._fetch_all()
    ~~~~~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 1954, in _fetch_all
    self._result_cache = list(self._iterable_class(self))
                         ~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/query.py", line 93, in __iter__
    results = compiler.execute_sql(
        chunked_fetch=self.chunked_fetch, chunk_size=self.chunk_size
    )
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/models/sql/compiler.py", line 1623, in execute_sql
    cursor.execute(sql, params)
    ~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 122, in execute
    return super().execute(sql, params)
           ~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 79, in execute
    return self._execute_with_wrappers(
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~^
        sql, params, many=False, executor=self._execute
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    )
    ^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 92, in _execute_with_wrappers
    return executor(sql, params, many, context)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 100, in _execute
    with self.db.wrap_database_errors:
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/utils.py", line 91, in __exit__
    raise dj_exc_value.with_traceback(traceback) from exc_value
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/utils.py", line 105, in _execute
    return self.cursor.execute(sql, params)
           ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/django/db/backends/mysql/base.py", line 76, in execute
    return self.cursor.execute(query, args)
           ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/cursors.py", line 153, in execute
    result = self._query(query)
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/cursors.py", line 322, in _query
    conn.query(q)
    ~~~~~~~~~~^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 563, in query
    self._affected_rows = self._read_query_result(unbuffered=unbuffered)
                          ~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 825, in _read_query_result
    result.read()
    ~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 1199, in read
    first_packet = self.connection._read_packet()
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/connections.py", line 775, in _read_packet
    packet.raise_for_error()
    ~~~~~~~~~~~~~~~~~~~~~~^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/protocol.py", line 219, in raise_for_error
    err.raise_mysql_exception(self._data)
    ~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^
  File "/Users/zigma-mac/Documents/IWMS/iwms-government-backend/.venv/lib/python3.14/site-packages/pymysql/err.py", line 150, in raise_mysql_exception
    raise errorclass(errno, errval)
django.db.utils.OperationalError: (1054, "Unknown column 'app_dailytriphouseholdcollection.carried_to_assignment_id' in 'field list'")
