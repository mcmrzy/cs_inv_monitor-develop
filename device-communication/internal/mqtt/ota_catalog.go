package mqtt

import (
	"context"
	"encoding/json"
	"errors"
	"strings"

	"github.com/eclipse/paho.golang/paho"
)

func (c *Client) SetPanelQueryHandler(handler func(string, []byte) bool) { c.onPanelQuery = handler }

// Handle catalog traffic before the generic OTA and heartbeat handlers.
func (c *Client) dispatchPanelRPC(topic string, payload []byte, retained bool) bool {
	parts := strings.Split(topic, "/")
	if len(parts) != 4 || parts[0] != "cs_inv" || parts[2] != "ota" {
		return false
	}
	if parts[3] == "cmd" && len(payload) <= 1800 {
		// The broker echoes catalog replies to the server's wildcard subscription.
		var reply struct {
			Action string `json:"action"`
		}
		return json.Unmarshal(payload, &reply) == nil && reply.Action == "catalog"
	}
	if parts[3] != "status" || len(payload) > 512 {
		return false
	}
	var envelope struct {
		Data struct {
			Type string `json:"type"`
		} `json:"data"`
	}
	if json.Unmarshal(payload, &envelope) != nil || envelope.Data.Type != "catalog.query" {
		return false
	}
	if !retained && c.onPanelQuery != nil {
		c.onPanelQuery(parts[1], payload)
	}
	return true
}
func (c *Client) PublishPanelRPC(ctx context.Context, sn string, payload []byte) error {
	if c.cm == nil {
		return errors.New("MQTT is not connected")
	}
	if len(payload) > 1800 {
		return errors.New("firmware catalog reply exceeds device limit")
	}
	_, err := c.cm.Publish(ctx, &paho.Publish{Topic: "cs_inv/" + sn + "/ota/cmd", Payload: payload, QoS: 1, Retain: false})
	return err
}
