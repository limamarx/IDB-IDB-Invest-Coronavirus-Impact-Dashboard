create table {{ athena_database }}.{{ slug }}_{{ raw_table }}_{{ name }}_{{ p_name }}
with (
      external_location = '{{ s3_path }}/{{ slug }}/{{ current_millis }}/{{ raw_table }}/{{ name }}/{{ p_path }}',
	  format='orc', orc_compression = 'ZLIB'
      ) as
with t as (
	with raw as (
		select 
			cast(uuid as varchar) uuid,
			 country, 
			city, length, line_wkt as line, 
			from_unixtime(retrievaltime/1000) retrievaltime,
		-- 	date_parse(rpad(cast(at_timezone(
		-- 	from_unixtime(retrievaltime/1000), (select timezone 
		-- 					from {{ athena_database }}.{{ slug }}_analysis_metadata_variation 
		-- 					where region_slug = '{{ partition }}')
		-- ) as varchar), 19, '000'), '%Y-%m-%d %k:%i:%s') retrievaltime,
			datetime
		from pwazetransformeddb.jams
		where regexp_like(datetime, '{{ date_filter }}')
		and st_intersects(
			st_polygon('{{ region_shapefile_wkt | replace('"', '') }}'), st_line(line_wkt))
		and
		{% for filter in initial_filters %}
		{%- if loop.last -%}
			{{ filter }}
		{%- else -%}
			{{ filter }} and
		{%- endif %} 
		{% endfor %}
	)
	select 
		length,
		line,
 		retrievaltime,
		row_number() over (partition by uuid, year(retrievaltime), month(retrievaltime), day(retrievaltime),
								date_parse(format_datetime(date_add('minute', 
									cast(date_diff('minute',
										timestamp '{{ reference_timestamp }}', retrievaltime) / {{ feed_frequency }} as bigint) * {{ feed_frequency }},
										timestamp '{{ reference_timestamp }}'), 'H:m'), '%H:%i') order by retrievaltime) n_row
	from raw)
select 
	year(retrievaltime) as year,
	month(retrievaltime) as month,
	day(retrievaltime) as day,
	hour(retrievaltime) as hour,
	day_of_week(retrievaltime) as dow,
	line,
	cast(sum(length) as bigint) as tci
from t
where n_row = 1
group by
	year(retrievaltime),
	month(retrievaltime),
	day(retrievaltime),
	hour(retrievaltime),
	day_of_week(retrievaltime),
	line