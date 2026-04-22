package core

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type scenariosFile struct {
	Scenarios []Scenario `yaml:"scenarios"`
}

// LoadScenarios parses the given YAML file and returns all scenarios.
func LoadScenarios(path string) ([]Scenario, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read scenarios file: %w", err)
	}
	var f scenariosFile
	if err := yaml.Unmarshal(data, &f); err != nil {
		return nil, fmt.Errorf("parse scenarios YAML: %w", err)
	}
	return f.Scenarios, nil
}
