//go:build integration

package repository

import (
	"context"
	"sync"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestAssignUnassignedToStation(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,nickname,status) VALUES
		(99301,'assignment-owner','hash','Owner',1),(99302,'assignment-other','hash','Other',1);
		INSERT INTO stations(id,user_id,name,province,city,address,capacity,timezone) VALUES
		(99301,99301,'First','','','',0,'UTC'),
		(99302,99301,'Second','','','',0,'Asia/Shanghai'),
		(99303,99302,'Other','','','',0,'UTC');
		INSERT INTO devices(sn,model,user_id,rated_power) VALUES('ASSIGNMENT-TEST','L10',99301,10000);`)
	require.NoError(t, err)
	repo := NewDeviceRepository(pool, nil)
	for _, station := range []int64{99303, 99999} {
		assigned, err := repo.AssignUnassignedToStation(ctx, "ASSIGNMENT-TEST", station, 99301)
		require.NoError(t, err)
		require.False(t, assigned, "foreign or missing station cannot receive device")
	}
	assigned, err := repo.AssignUnassignedToStation(ctx, "ASSIGNMENT-TEST", 99301, 99302)
	require.NoError(t, err)
	require.False(t, assigned, "changed device owner cannot assign")
	assigned, err = repo.AssignUnassignedToStation(ctx, "ASSIGNMENT-TEST", 99301, 99301)
	require.NoError(t, err)
	require.True(t, assigned)
	assigned, err = repo.AssignUnassignedToStation(ctx, "ASSIGNMENT-TEST", 99302, 99301)
	require.NoError(t, err)
	require.False(t, assigned, "stale selection must not move an assigned device")
	var stationID int64
	var timezone string
	require.NoError(t, pool.QueryRow(ctx, `SELECT station_id,timezone FROM devices WHERE sn='ASSIGNMENT-TEST'`).Scan(&stationID, &timezone))
	require.EqualValues(t, 99301, stationID)
	require.Equal(t, "UTC", timezone)

	// Explicit rebind keeps its existing contract, independent of guarded addition.
	require.NoError(t, repo.AddToStation(ctx, "ASSIGNMENT-TEST", 99302))
	require.NoError(t, pool.QueryRow(ctx, `SELECT station_id FROM devices WHERE sn='ASSIGNMENT-TEST'`).Scan(&stationID))
	require.EqualValues(t, 99302, stationID)

	require.NoError(t, repo.RemoveFromStation(ctx, "ASSIGNMENT-TEST"))
	var wg sync.WaitGroup
	results := make(chan bool, 2)
	for _, station := range []int64{99301, 99302} {
		wg.Add(1)
		go func(station int64) {
			defer wg.Done()
			assigned, err := repo.AssignUnassignedToStation(ctx, "ASSIGNMENT-TEST", station, 99301)
			if err != nil {
				t.Errorf("concurrent assignment: %v", err)
			}
			results <- assigned
		}(station)
	}
	wg.Wait()
	close(results)
	winners := 0
	for assigned := range results {
		if assigned {
			winners++
		}
	}
	require.Equal(t, 1, winners, "only one concurrent addition can succeed")
}
