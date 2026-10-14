package service

import (
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

const testBindingSN = "H1ZZX0013900001P"
const testBindingNonce = "0123456789abcdef0123456789abcdef"

func bindingTestKey() ed25519.PrivateKey { return ed25519.NewKeyFromSeed(make([]byte, 32)) }
func TestBindingSignatureVector(t *testing.T) {
	q := BindingQuery{SN: testBindingSN, Nonce: testBindingNonce}
	signed, err := SignBindingState(bindingTestKey(), q, "UNBOUND", "17")
	if err != nil {
		t.Fatal(err)
	}
	canonical := "CSERGY-BINDING-V1\nH1ZZX0013900001P\nUNBOUND\n17\n0123456789abcdef0123456789abcdef\n"
	if string(BindingCanonical(signed)) != canonical {
		t.Fatalf("incorrect canonical %q", BindingCanonical(signed))
	}
	signature, _ := hex.DecodeString(signed.Signature)
	pub := bindingTestKey().Public().(ed25519.PublicKey)
	if !ed25519.Verify(pub, []byte(canonical), signature) {
		t.Fatal("signature verification failed")
	}
	raw, _ := json.Marshal(signed)
	if !strings.Contains(string(raw), `"key_id":1`) || !strings.Contains(string(raw), `"sn":"H1ZZX0013900001P"`) {
		t.Fatalf("wrong wire object: %s", raw)
	}
	t.Logf("public_key=%s signature=%s", hex.EncodeToString(pub), signed.Signature)
	signed.Revision = "18"
	if ed25519.Verify(pub, BindingCanonical(signed), signature) {
		t.Fatal("changed revision verified")
	}
}
func TestBindingQueryAndSignerRejectBadInput(t *testing.T) {
	valid := []byte(`{"data":{"sn":"H1ZZX0013900001P","nonce":"0123456789abcdef0123456789abcdef"}}`)
	if _, err := ParseBindingQuery(testBindingSN, valid); err != nil {
		t.Fatal(err)
	}
	for _, raw := range [][]byte{[]byte(`{}`), []byte(`{"data":{"sn":"OTHER","nonce":"bad"}}`), make([]byte, 513), []byte(`{"sn":"H1ZZX0013900001P"}`)} {
		if _, err := ParseBindingQuery(testBindingSN, raw); err == nil {
			t.Fatal("invalid query accepted")
		}
	}
	if _, err := ParseBindingQuery("OTHER", valid); err == nil {
		t.Fatal("topic mismatch accepted")
	}
	q := BindingQuery{SN: testBindingSN, Nonce: testBindingNonce}
	for _, revision := range []string{"-1", "01", "9223372036854775808", "0"} {
		if _, err := SignBindingState(bindingTestKey(), q, "BOUND", revision); err == nil {
			t.Fatal("invalid revision accepted")
		}
	}
	if _, err := SignBindingState(bindingTestKey(), q, "UNKNOWN", "0"); err != nil {
		t.Fatal(err)
	}
	if _, err := BindingSigningKey("bad"); err == nil {
		t.Fatal("bad seed accepted")
	}
	if key, err := BindingSigningKey(""); err != nil || key != nil {
		t.Fatal("blank key must disable")
	}
}

type bindingMockRepo struct{ fail bool }

func (r bindingMockRepo) BindingSnapshot(context.Context, string) (string, string, error) {
	if r.fail {
		return "", "", errors.New("database unavailable")
	}
	return "BOUND", "19", nil
}

type bindingMockPublisher struct {
	payload []byte
	calls   int
}

func (p *bindingMockPublisher) PublishBindingState(_ context.Context, sn string, raw []byte) error {
	if sn != testBindingSN {
		panic("wrong topic SN")
	}
	p.payload = raw
	p.calls++
	return nil
}
func TestBindingResponderAndBoundedQueue(t *testing.T) {
	pub := &bindingMockPublisher{}
	s := NewDeviceBindingStateService(bindingMockRepo{}, pub, bindingTestKey())
	raw := []byte(`{"data":{"sn":"H1ZZX0013900001P","nonce":"0123456789abcdef0123456789abcdef"}}`)
	for i := 0; i < 64; i++ {
		if !s.Enqueue(testBindingSN, raw) {
			t.Fatal("queue capacity")
		}
	}
	if s.Enqueue(testBindingSN, raw) {
		t.Fatal("queue unbounded")
	}
	if err := s.respond(context.Background(), <-s.queue); err != nil {
		t.Fatal(err)
	}
	var response BindingState
	if err := json.Unmarshal(pub.payload, &response); err != nil || response.Nonce != testBindingNonce || response.State != "BOUND" {
		t.Fatal("wrong response")
	}
	s.repo = bindingMockRepo{fail: true}
	if err := s.respond(context.Background(), BindingQuery{SN: testBindingSN, Nonce: testBindingNonce}); err == nil || pub.calls != 1 {
		t.Fatal("database failure must not fabricate state")
	}
	disabled := NewDeviceBindingStateService(bindingMockRepo{}, pub, nil)
	if disabled.Enqueue(testBindingSN, raw) {
		t.Fatal("disabled signer accepted query")
	}
}
