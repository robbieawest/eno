package ecs

// Does not store much actual data, just points to the archetype memory
Component :: struct {
    label: string,
    type: typeid,
    data: []byte
}
