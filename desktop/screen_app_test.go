package main

import (
	"image"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestCropPNG(t *testing.T) {
	path := filepath.Join(t.TempDir(), "shot.png")
	f, _ := os.Create(path)
	png.Encode(f, image.NewNRGBA(image.Rect(0, 0, 200, 100)))
	f.Close()

	if err := cropPNG(path, 0.25, 0.5, 0.5, 0.5); err != nil {
		t.Fatal(err)
	}
	f, _ = os.Open(path)
	img, err := png.Decode(f)
	f.Close()
	if err != nil {
		t.Fatal(err)
	}
	if b := img.Bounds(); b.Dx() != 100 || b.Dy() != 50 {
		t.Fatalf("cropped to %v", b)
	}
	if err := cropPNG(path, 0.5, 0.5, 0.001, 0.001); err == nil {
		t.Fatal("a tiny box should be refused")
	}
}
