package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5"
)

func main() {
	ctx := context.Background()
	connStr := "postgres://postgres:@localhost:5432/inv_mqtt?sslmode=disable"
	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect failed: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	sn := "11111DAWD"
	startDate := "2026-07-01"
	endDate := "2026-07-17"
	tz := "Asia/Shanghai"

	// ========== Test GetHistoryData ==========
	fmt.Println("=== GetHistoryData: period=hour (4 params) ===")
	hourQuery := `
		SELECT bucket, avg_ac_power, max_ac_power, daily_pv_energy,
		       avg_inverter_temperature, run_minutes
		FROM device_telemetry_hour
		WHERE device_sn=$1 AND bucket >= ($2::date::timestamp AT TIME ZONE $4)
		  AND bucket < (($3::date + 1)::timestamp AT TIME ZONE $4)
		ORDER BY bucket`
	rows, err := conn.Query(ctx, hourQuery, sn, startDate, endDate, tz)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR hour: %v\n", err)
	} else {
		count := 0
		for rows.Next() {
			count++
		}
		fmt.Printf("OK: %d rows returned\n", count)
		rows.Close()
	}

	fmt.Println("\n=== GetHistoryData: period=day (3 params) ===")
	dayQuery := `
		SELECT stat_date::timestamptz, NULL::double precision, max_ac_power,
		       pv_energy, max_inverter_temperature, run_minutes
		FROM device_energy_day
		WHERE device_sn=$1 AND stat_date >= $2::date AND stat_date <= $3::date
		ORDER BY stat_date`
	rows2, err := conn.Query(ctx, dayQuery, sn, startDate, endDate)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR day: %v\n", err)
	} else {
		count := 0
		for rows2.Next() {
			count++
		}
		fmt.Printf("OK: %d rows returned\n", count)
		rows2.Close()
	}

	// Bug scenario: pass 4 args to 3-param query
	fmt.Println("\n=== BUG TEST: 3-param SQL but 4 args (should fail in pgx v5) ===")
	rows3, err := conn.Query(ctx, dayQuery, sn, startDate, endDate, tz)
	if err != nil {
		fmt.Fprintf(os.Stderr, "EXPECTED ERROR: %v\n", err)
	} else {
		fmt.Println("Unexpectedly succeeded (pgx may tolerate extra args)")
		rows3.Close()
	}

	// ========== Test GetStatistics ==========
	fmt.Println("\n=== GetStatistics: single query (3 params) ===")
	today := "2026-07-17"
	monthStart := "2026-07-01"
	statsQuery := `
		SELECT COALESCE(MAX(pv_energy) FILTER (WHERE stat_date=$2::date),0),
		       COALESCE(
		           (SELECT m.pv_energy FROM device_energy_month m
		            WHERE m.device_sn=$1 AND m.stat_month=$3::date),
		           SUM(pv_energy) FILTER (WHERE stat_date >= $3::date),
		           0
		       ),
		       COALESCE(SUM(pv_energy),0),
		       COALESCE(MAX(discharge_energy) FILTER (WHERE stat_date=$2::date),0)
		FROM device_energy_day WHERE device_sn=$1`
	row := conn.QueryRow(ctx, statsQuery, sn, today, monthStart)
	var dailyEnergy, monthlyEnergy, totalEnergy, dailyDischarge float64
	err = row.Scan(&dailyEnergy, &monthlyEnergy, &totalEnergy, &dailyDischarge)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR stats: %v\n", err)
	} else {
		fmt.Printf("OK: daily=%.2f monthly=%.2f total=%.2f discharge=%.2f\n",
			dailyEnergy, monthlyEnergy, totalEnergy, dailyDischarge)
	}

	// ========== Test StationRepository.GetStatistics ==========
	fmt.Println("\n=== StationRepo.GetStatistics: period=hour (4 params) ===")
	stationHourQuery := `SELECT h.bucket, SUM(h.avg_pv_power), SUM(h.avg_ac_power), SUM(h.avg_battery_power),
		SUM(h.daily_pv_energy),
		SUM(GREATEST(h.avg_battery_power, 0)) / 1000.0,
		SUM(GREATEST(-h.avg_battery_power, 0)) / 1000.0,
		SUM(h.avg_ac_power) / 1000.0
		FROM device_telemetry_hour h JOIN devices d ON d.sn=h.device_sn
		WHERE d.station_id=$1 AND d.deleted_at IS NULL AND h.bucket >= ($2::date::timestamp AT TIME ZONE $4)
		AND h.bucket < (($3::date+1)::timestamp AT TIME ZONE $4) GROUP BY h.bucket ORDER BY h.bucket`
	rows4, err := conn.Query(ctx, stationHourQuery, int64(1), startDate, endDate, tz)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR station hour: %v\n", err)
	} else {
		count := 0
		for rows4.Next() {
			count++
		}
		fmt.Printf("OK: %d rows returned\n", count)
		rows4.Close()
	}

	fmt.Println("\n=== StationRepo.GetStatistics: period=day (3 params) ===")
	stationDayQuery := `SELECT e.stat_date::timestamptz, SUM(e.pv_energy), SUM(e.max_ac_power), NULL::double precision,
		SUM(e.pv_energy),SUM(e.charge_energy),SUM(e.discharge_energy),SUM(e.load_energy)
		FROM device_energy_day e JOIN devices d ON d.sn=e.device_sn
		WHERE d.station_id=$1 AND d.deleted_at IS NULL AND e.stat_date >= $2::date AND e.stat_date <= $3::date
		GROUP BY e.stat_date ORDER BY e.stat_date`
	rows5, err := conn.Query(ctx, stationDayQuery, int64(1), startDate, endDate)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR station day: %v\n", err)
	} else {
		count := 0
		for rows5.Next() {
			count++
		}
		fmt.Printf("OK: %d rows returned\n", count)
		rows5.Close()
	}

	// Bug scenario for station
	fmt.Println("\n=== BUG TEST: station day 3-param SQL but 4 args ===")
	rows6, err := conn.Query(ctx, stationDayQuery, int64(1), startDate, endDate, tz)
	if err != nil {
		fmt.Fprintf(os.Stderr, "EXPECTED ERROR: %v\n", err)
	} else {
		fmt.Println("Unexpectedly succeeded (pgx may tolerate extra args)")
		rows6.Close()
	}

	fmt.Println("\n=== ALL TESTS DONE ===")
}
