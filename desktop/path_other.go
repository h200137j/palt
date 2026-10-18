//go:build !linux && !darwin

package main

func pathKind(string) string { return "lan" }

func pathSpeed(string) int { return 1 }
