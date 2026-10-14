package mqtt

import "testing"

func TestBindingExactDispatchConsumesOwnState(t *testing.T) {
	calls := 0
	c := &Client{}
	c.SetBindingQueryHandler(func(sn string, payload []byte) bool {
		calls++
		if sn != "H1ZZX0013900001P" {
			t.Fatal("wrong SN")
		}
		return true
	})
	if !c.dispatchBinding("cs_inv/H1ZZX0013900001P/binding/query", []byte(`{}`)) || calls != 1 {
		t.Fatal("query not dispatched")
	}
	if !c.dispatchBinding("cs_inv/H1ZZX0013900001P/binding/state", []byte(`{}`)) || calls != 1 {
		t.Fatal("own state echoed to device activity or query handler")
	}
	for _, topic := range []string{"cs_inv/H1ZZX0013900001P/status", "cs_inv/H1ZZX0013900001P/binding/query/extra", "other/H1ZZX0013900001P/binding/query"} {
		if c.dispatchBinding(topic, nil) {
			t.Fatal("unrelated topic consumed")
		}
	}
}
