package mqtt

import (
	"context"
	"errors"
	"github.com/eclipse/paho.golang/paho"
	"strings"
)

func bindingTopic(topic string) (sn, kind string) {
	parts := strings.Split(topic, "/")
	if len(parts) == 4 && parts[0] == "cs_inv" && parts[2] == "binding" &&
		(parts[3] == "query" || parts[3] == "state") {
		return parts[1], parts[3]
	}
	return "", ""
}
func (c *Client) SetBindingQueryHandler(handler func(string, []byte) bool) {
	c.onBindingQuery = handler
}

// State responses are consumed here too: wildcard subscription must not count
// the server's own response as a device heartbeat.
func (c *Client) dispatchBinding(topic string, payload []byte) bool {
	sn, kind := bindingTopic(topic)
	if kind == "" {
		return false
	}
	if kind == "query" && c.onBindingQuery != nil {
		c.onBindingQuery(sn, payload)
	}
	return true
}
func (c *Client) PublishBindingState(ctx context.Context, sn string, payload []byte) error {
	if c.cm == nil {
		return errors.New("MQTT is not connected")
	}
	_, err := c.cm.Publish(ctx, &paho.Publish{Topic: "cs_inv/" + sn + "/binding/state", Payload: payload, QoS: 1, Retain: false})
	return err
}
