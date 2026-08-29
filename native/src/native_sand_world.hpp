#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <array>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "parallel_executor.hpp"
#include "thermal_prototype.hpp"

namespace godot {

class NativeSandWorld : public RefCounted {
    GDCLASS(NativeSandWorld, RefCounted)

public:
    static constexpr int32_t CHUNK_SIZE = 64;
    static constexpr int32_t CELLS_PER_CHUNK = CHUNK_SIZE * CHUNK_SIZE;
    static constexpr int32_t SLEEP_TICKS = 8;
    static constexpr int32_t MATERIAL_COUNT = 28;
    static constexpr int64_t FULL_CELL_MICRO_MASS = 65280;
    static constexpr int64_t AMOUNT_UNIT_MICRO_MASS = 256;
    static constexpr int32_t CONSTITUENT_COUNT = 6;
    static constexpr uint16_t TEMPERATURE_AMBIENT = 1173; // 293.25 K
    static constexpr uint16_t TEMPERATURE_REACTION = 5893; // 1473.25 K
    static constexpr uint16_t TEMPERATURE_MAX = 65535; // 16383.75 K

    NativeSandWorld();
    ~NativeSandWorld() override;

    void reset(int64_t world_seed = 1, int32_t requested_workers = 1);
    int32_t set_cell(Vector2i world_cell, int32_t material_id);
    int32_t set_cell_with_provenance(Vector2i world_cell, int32_t material_id, int32_t profile_id);
    int32_t set_cell_with_metadata(Vector2i world_cell, int32_t material_id, int32_t profile_id, int32_t mineral_signature);
    int32_t initialize_cell(Vector2i world_cell, int32_t material_id);
    int32_t get_cell(Vector2i world_cell) const;
    int32_t get_provenance(Vector2i world_cell) const;
    int32_t get_mineral_signature(Vector2i world_cell) const;
    int32_t harvest_cell(Vector2i world_cell);
    int32_t get_hidden_constituent(int32_t profile_id, int32_t mineral_signature) const;
    int32_t process_material_for_test(int32_t material_id, int32_t profile_id, int32_t mineral_signature, int32_t process_id) const;
    int64_t fill_rect(Rect2i area, int32_t material_id, int32_t spacing = 1);
    int32_t allocate_chunk_rect(Rect2i chunk_area);
    void finalize_initialization();
    int32_t step();

    int32_t chunk_count() const;
    int32_t active_chunk_count() const;
    int32_t sleeping_chunk_count() const;
    int64_t total_allocated_cells() const;
    int64_t simulation_backing_bytes() const;
    int64_t presentation_backing_bytes() const;
    int32_t get_worker_count() const;
    Array get_chunk_coordinates() const;
    Dictionary get_chunk_state(Vector2i coordinate) const;
    Dictionary get_statistics() const;
    Array consume_dirty_render_chunks();
    Dictionary consume_dirty_render_page(Rect2i chunk_area, bool force = false);
    PackedInt32Array get_non_empty_cells() const;
    String material_state_hash() const;
    String material_and_provenance_hash() const;

    void configure_world(Dictionary settings, int32_t generation_workers = 2);
    Dictionary get_world_settings() const;
    bool request_chunk(Vector2i coordinate, int32_t priority = 1);
    int32_t request_chunk_region(Rect2i chunk_area, int32_t priority = 1);
    int32_t pump_generation(int32_t max_publish = 4);
    int32_t flush_generation();
    bool is_chunk_generated(Vector2i coordinate) const;
    int32_t get_generation_state(Vector2i coordinate) const;
    int32_t evict_pristine_outside(Rect2i keep_chunk_area, int32_t max_evict = 16);
    Array consume_evicted_chunks();
    Dictionary get_generation_statistics() const;
    Dictionary get_world_identity() const;
    String get_generator_settings_hash() const;
    Dictionary get_worldgen_v2_architecture() const;
    Dictionary get_macro_sample(Vector2i macro_coordinate) const;
    Dictionary get_macro_preview(int32_t width = 160, int32_t height = 90) const;
    Array get_world_feature_templates() const;
    Array get_world_feature_anchors(Rect2i macro_area) const;
    Dictionary validate_world_seed(int64_t seed) const;
    Dictionary validate_world_seeds(int64_t first_seed, int32_t count) const;
    Dictionary get_worldgen_pass_hashes(Rect2i chunk_area) const;
    Dictionary get_worldgen_debug_sample(Rect2i cell_area, int32_t stride = 8) const;
    Vector2i get_character_spawn() const;
    Dictionary query_character_collision(Rect2i body) const;
    Dictionary character_dig_cell(Vector2i world_cell);
    Dictionary update_character_visibility(int64_t owner_id, Vector2i origin, int32_t radius = 72,
                                           int32_t solid_shell_depth = 8);
    bool is_cell_discovered(int64_t owner_id, Vector2i world_cell) const;
    bool is_cell_live_visible(int64_t owner_id, Vector2i world_cell) const;
    Dictionary get_visibility_render_page(int64_t owner_id, Rect2i chunk_area) const;
    Dictionary get_visibility_statistics(int64_t owner_id) const;
    void clear_visibility(int64_t owner_id = -1);
    Dictionary serialize_visibility_state(int64_t owner_id) const;
    bool deserialize_visibility_state(Dictionary state);
    String visibility_state_hash(int64_t owner_id) const;
    int32_t geology_profile_id_at(Vector2i world_cell) const;
    Dictionary get_geology_profile(int32_t profile_id) const;
    Dictionary get_geology_profile_at(Vector2i world_cell) const;
    String get_chunk_content_hash(Vector2i coordinate) const;
    String get_region_content_hash(Rect2i chunk_area) const;
    Array get_organic_material_definitions() const;
    Array get_fuel_definitions() const;
    Dictionary get_organic_architecture() const;
    Dictionary get_organic_state(Vector2i world_cell) const;
    int32_t set_organic_moisture(Vector2i world_cell, int32_t moisture);
    int32_t get_organic_moisture(Vector2i world_cell) const;
    Dictionary bind_water_to_sediment(Vector2i sediment_cell, Vector2i water_cell, int32_t requested_amount);
    int64_t get_bound_water_mass() const;
    int32_t get_oxidizer(Vector2i world_cell) const;
    Dictionary character_cut_cell(Vector2i world_cell);
    Dictionary clear_vegetation_rect(Rect2i area);
    Dictionary ignite_cell(Vector2i world_cell, int32_t energy = 180000);
    Array get_visible_fellable_clusters(Rect2i cell_area) const;
    PackedInt32Array get_visible_organic_effects(Rect2i cell_area) const;
    Dictionary get_organic_statistics() const;
    String organic_state_hash() const;
    Dictionary configure_phase12_benchmark(int32_t scenario, int32_t count);
    Dictionary get_thermal_vessel_definition(int32_t type_id) const;
    Dictionary get_conservation_architecture() const;
    Dictionary derive_material_composition(int32_t profile_id, int32_t mineral_signature) const;
    Dictionary run_fractionation_fixture(int32_t numerator, int32_t denominator, int32_t input_count,
                                         int32_t route = 0) const;
    Dictionary run_variable_composition_fixture(Array gold_numerators, int32_t denominator,
                                                int32_t route = 0) const;
    Dictionary run_global_mass_fixture(int32_t input_count, int32_t profile_id, int32_t mineral_signature) const;
    Dictionary accumulate_fraction_for_test(int64_t ledger_id, int32_t numerator, int32_t denominator,
                                            int32_t route = 0, bool output_available = true);
    Dictionary get_fractional_ledger(int64_t ledger_id) const;
    Dictionary get_component_classification() const;
    Dictionary get_structure_physical_properties(int32_t type_id) const;
    Dictionary serialize_world_snapshot() const;
    bool deserialize_world_snapshot(Dictionary state);
    String phase13_state_hash() const;
    Dictionary get_milestone_state() const;
    Dictionary evaluate_mvp_playthrough(int32_t minutes, int32_t profile_id = 4590) const;

    Array get_structure_definitions() const;
    Dictionary get_memory_layout() const;
    bool can_place_structure(int32_t type_id, Vector2i origin, int32_t orientation = 0) const;
    int64_t place_structure(int32_t type_id, Vector2i origin, int32_t orientation = 0);
    Dictionary apply_structure_batch(PackedInt32Array operations, int32_t validation_mode = 0);
    bool can_place_subsurface_channel(int32_t depth, Vector2i entrance, Vector2i exit) const;
    int64_t place_subsurface_channel(int32_t depth, Vector2i entrance, Vector2i exit);
    bool remove_subsurface_channel(int64_t channel_id, int32_t removal_policy = 1);
    Dictionary get_subsurface_channel_state(int64_t channel_id) const;
    PackedInt32Array get_visible_subsurface_routes(Rect2i cell_area) const;
    Dictionary get_subsurface_statistics() const;
    Dictionary get_factory_foundation_architecture() const;
    Dictionary get_production_statistics() const;
    Dictionary benchmark_production_events(int32_t event_count = 1000000);
    bool record_production_event_for_test(int32_t material_id, int64_t amount, bool produced);
    Dictionary serialize_subsurface_state() const;
    bool deserialize_subsurface_state(Dictionary state);
    String subsurface_state_hash() const;
    bool seed_subsurface_packet_for_test(int64_t channel_id, int32_t lane_index, int32_t material_id,
                                         int32_t temperature = TEMPERATURE_AMBIENT, int32_t provenance = 0, int32_t signature = 0);
    bool can_place_conveyor_line(Vector2i from, Vector2i to, int32_t direction) const;
    int32_t place_conveyor_line(Vector2i from, Vector2i to, int32_t direction);
    int32_t place_pipe_line(Vector2i from, Vector2i to);
    int32_t remove_structure_at(Vector2i world_cell);
    int32_t remove_structures_rect(Rect2i area);
    int32_t get_structure(Vector2i world_cell) const;
    PackedInt32Array get_visible_structure_cells(Rect2i chunk_area) const;
    PackedInt32Array get_visible_machine_entities(Rect2i chunk_area) const;
    Array consume_dirty_structure_chunks();
    Dictionary get_structure_statistics() const;
    Dictionary get_processing_statistics() const;
    Dictionary get_physical_processing_statistics() const;
    Dictionary get_magnetic_field_sample(Rect2i cell_area, int32_t stride = 2) const;
    int32_t get_grain_size_class(Vector2i world_cell) const;
    int32_t get_magnetic_susceptibility(Vector2i world_cell) const;
    int32_t get_temperature(Vector2i world_cell) const;
    int32_t set_material_state(Vector2i world_cell, int32_t material_id, int32_t amount = 255,
                               int32_t temperature = TEMPERATURE_AMBIENT, int32_t provenance = 0,
                               int32_t mineral_signature = 0);
    int64_t fill_rect_state(Rect2i area, int32_t material_id, int32_t amount = 255,
                            int32_t temperature = TEMPERATURE_AMBIENT);
    int64_t fill_pattern_state(Rect2i area, int32_t material_id, int32_t amount_a, int32_t amount_b,
                               int32_t temperature_a, int32_t temperature_b);
    int32_t get_material_amount(Vector2i world_cell) const;
    int32_t get_phase_energy(Vector2i world_cell) const;
    int64_t get_total_phase_family_mass(int32_t family_id) const;
    int64_t get_total_thermal_enthalpy() const;
    Dictionary get_material_thermal_definition(int32_t material_id) const;
    Dictionary get_thermal_statistics() const;
    Dictionary get_gas_statistics() const;
    Dictionary get_phase9_architecture() const;
    bool set_thermal_switch_open(Vector2i world_cell, bool open);
    int32_t set_water_mass(Vector2i world_cell, int32_t mass, int32_t temperature = TEMPERATURE_AMBIENT);
    int32_t get_liquid_mass(Vector2i world_cell) const;
    int64_t get_total_water_mass() const;
    Dictionary get_fluid_statistics() const;
    Dictionary get_fluid_render_page(Rect2i chunk_area) const;
    Dictionary get_temperature_sample(Rect2i cell_area, int32_t stride = 4) const;
    Dictionary get_temperature_render_page(Rect2i chunk_area) const;
    void configure_thermal_candidate(int32_t width = 1024, int32_t height = 512, int32_t workers = 8);
    Dictionary step_thermal_candidate(int32_t cadence_scale = 2);
    Dictionary get_thermal_candidate_statistics() const;
    String authoritative_physical_hash() const;
    int32_t set_pipe_mass(Vector2i world_cell, int32_t mass, int32_t temperature = TEMPERATURE_AMBIENT);
    int32_t set_pipe_fluid(Vector2i world_cell, int32_t fluid_type, int32_t mass,
                           int32_t temperature = TEMPERATURE_AMBIENT);
    Dictionary get_pipe_state(Vector2i world_cell) const;
    Dictionary get_pipe_statistics() const;
    PackedInt32Array get_visible_pipe_segments(Rect2i chunk_area) const;
    Dictionary get_infrastructure_render_page(Vector2i chunk_coordinate) const;
    int64_t get_total_pipe_water_mass() const;
    int64_t get_total_conserved_water_mass() const;
    int64_t get_total_pipe_water_phase_mass() const;
    int64_t get_total_conserved_water_phase_mass() const;
    bool set_pipe_device_enabled(Vector2i world_cell, bool enabled);
    bool set_pipe_valve_open(Vector2i world_cell, bool open);
    int32_t damage_pipe(Vector2i world_cell, int32_t damage, int32_t cause = 0);
    String pipe_state_hash() const;
    Dictionary get_wet_processing_statistics() const;
    String physical_processing_hash() const;
    Dictionary get_machine_state_at(Vector2i world_cell) const;
    Dictionary evaluate_processing_routes(int32_t profile_id, int32_t sample_count = 100000) const;
    String logistics_state_hash() const;
    String processing_state_hash() const;

    void set_game_mode(int32_t mode);
    int32_t get_game_mode() const;
    void initialize_progression();
    Array get_research_definitions() const;
    Dictionary get_progression_state() const;
    Dictionary get_research_state(String research_id) const;
    bool try_unlock_research(String research_id);
    bool is_structure_unlocked(int32_t type_id) const;
    Dictionary serialize_progression_state() const;
    bool deserialize_progression_state(Dictionary state);
    bool credit_research_material_for_test(int32_t material_id, int64_t amount);
    Dictionary get_bank_statistics() const;
    Dictionary evaluate_progression_pacing(int32_t profile_id, int32_t sample_limit = 200000) const;

    Array get_automation_definitions() const;
    int64_t create_automation_component(int32_t type_id, Vector2i position, Dictionary configuration = Dictionary());
    bool remove_automation_component(int64_t component_id);
    bool configure_automation_component(int64_t component_id, Dictionary configuration);
    bool set_manual_switch(int64_t component_id, bool enabled);
    int64_t create_automation_connection(int64_t source_component, int32_t source_port, int64_t target_component, int32_t target_port);
    bool remove_automation_connection(int64_t connection_id);
    int32_t remove_component_connections(int64_t component_id);
    Array get_automation_component_ports(int64_t component_id) const;
    Dictionary get_automation_component_state(int64_t component_id) const;
    Dictionary get_automation_subgraph(int64_t component_id, int32_t max_components = 256) const;
    PackedInt32Array get_visible_automation_components(Rect2i cell_area) const;
    PackedInt32Array get_visible_automation_connections(Rect2i cell_area) const;
    Dictionary get_automation_statistics() const;
    Dictionary serialize_automation_state() const;
    bool deserialize_automation_state(Dictionary state);
    String automation_state_hash() const;
    bool set_automation_input_for_test(int64_t component_id, int32_t port, int32_t value);

    int32_t place_mechanical_shaft_line(Vector2i from, Vector2i to);
    bool configure_power_structure(Vector2i world_cell, Dictionary configuration);
    bool set_power_switch_closed(Vector2i world_cell, bool closed);
    bool set_power_consumer_priority(Vector2i world_cell, int32_t priority);
    Dictionary get_power_state_at(Vector2i world_cell) const;
    Dictionary get_power_network_state(int64_t network_id) const;
    Dictionary get_power_statistics() const;
    Dictionary get_mechanical_statistics() const;
    Dictionary get_energy_accounting() const;
    Dictionary get_phase10_architecture() const;
    PackedInt32Array get_visible_power_elements(Rect2i cell_area) const;
    String power_state_hash() const;
    Dictionary serialize_power_state() const;
    bool deserialize_power_state(Dictionary state);
    Dictionary configure_power_benchmark(int32_t scenario, int32_t count);

protected:
    static void _bind_methods();

private:
    struct Bounds {
        int16_t min_x = CHUNK_SIZE;
        int16_t min_y = CHUNK_SIZE;
        int16_t max_x = -1;
        int16_t max_y = -1;

        bool valid() const { return max_x >= min_x && max_y >= min_y; }
        int32_t area() const {
            return valid() ? (max_x - min_x + 1) * (max_y - min_y + 1) : 0;
        }
        void clear();
        void include(int32_t x, int32_t y, int32_t radius = 0);
        void merge(const Bounds &other);
    };

    struct FluidActivity {
        uint64_t rows = 0;
        std::array<uint8_t, CHUNK_SIZE> min_x{};
        std::array<uint8_t, CHUNK_SIZE> max_x{};

        FluidActivity();
        bool valid() const { return rows != 0; }
        void clear();
        void include(int32_t x, int32_t y, int32_t radius = 0);
        void merge(const FluidActivity &other);
        int32_t area() const;
    };

    struct Chunk {
        Vector2i coordinate;
        std::array<uint16_t, CELLS_PER_CHUNK> material{};
        std::array<uint16_t, CELLS_PER_CHUNK> temperature{};
        std::array<uint8_t, CELLS_PER_CHUNK> flags{};
        std::array<uint16_t, CELLS_PER_CHUNK> provenance{};
        std::array<uint16_t, CELLS_PER_CHUNK> mineral_signature{};
        std::array<uint8_t, CELLS_PER_CHUNK * 4> rgba{};
        std::unique_ptr<std::array<uint8_t, CELLS_PER_CHUNK>> structures;
        // Generic 0..255 material amount override. Full occupied cells remain implicit 255.
        std::unique_ptr<std::array<uint8_t, CELLS_PER_CHUNK>> material_amount;
        // Latent transition progress or exact sub-temperature enthalpy remainder. Lazy per chunk.
        std::unique_ptr<std::array<uint16_t, CELLS_PER_CHUNK>> phase_energy;
        std::unique_ptr<std::array<uint8_t, CELLS_PER_CHUNK>> organic_moisture;
        std::unique_ptr<std::array<uint8_t, CELLS_PER_CHUNK>> oxidizer;
        std::unique_ptr<std::array<uint16_t, CELLS_PER_CHUNK>> reaction_progress;
        std::unique_ptr<std::array<uint8_t, CELLS_PER_CHUNK>> reaction_state;
        std::unique_ptr<std::array<int32_t, CELLS_PER_CHUNK>> thermal_right_transfer;
        std::unique_ptr<std::array<int32_t, CELLS_PER_CHUNK>> thermal_down_transfer;
        Bounds active;
        Bounds next_active;
        FluidActivity fluid_active;
        FluidActivity fluid_next_active;
        FluidActivity thermal_active;
        FluidActivity thermal_next_active;
        Bounds render_dirty;
        uint64_t revision = 0;
        int32_t stable_ticks = 0;
        bool moved_this_tick = false;
        bool generated = false;
        bool pristine = false;
        bool structure_render_dirty = false;
        uint16_t fluid_plane_quiet_ticks = 0;
        uint16_t thermal_quiet_ticks = 0;
        bool fluid_moved_this_tick = false;

        explicit Chunk(Vector2i chunk_coordinate);
    };

    struct StructureDefinition {
        int32_t type_id;
        const char *display_name;
        const char *category;
        const char *unlock_key;
        int16_t width;
        int16_t height;
        bool tile_like;
        bool directional;
        std::vector<Vector2i> occupied;
        std::vector<Vector2i> input_ports;
        std::vector<Vector2i> output_ports;
    };

    struct MachineEntity {
        uint64_t id = 0;
        int32_t type_id = 0;
        Vector2i origin;
        int32_t orientation = 0;
        uint16_t input_material = 0;
        uint16_t input_provenance = 0;
        uint16_t input_signature = 0;
        uint16_t result_material = 0;
        uint16_t result_provenance = 0;
        uint16_t result_signature = 0;
        uint16_t ash_material = 0;
        int32_t fuel_remaining = 0;
        int32_t progress_ticks = 0;
        int32_t state = 0;
        int64_t processed_cells = 0;
        int64_t emitted_cells = 0;
        int64_t last_process_tick = 0;
        int32_t last_route = 0;
        bool control_connected = false;
        bool control_enabled = true;
    };

    struct PhysicalProcessor {
        uint64_t id = 0;
        int32_t type_id = 0;
        Vector2i origin;
        int32_t orientation = 0;
        Rect2i interaction_area;
        int16_t field_strength = 0;
        int8_t transport_direction = 1;
        uint8_t aperture = 0;
    };

    enum class PhysicalFieldKind : uint8_t {
        MAGNETIC = 0,
        AIRFLOW = 1,
        HEAT_SOURCE = 2,
        GRAVITY_MODIFIER = 3,
        RADIATION = 4,
    };

    struct PhysicalFieldSource {
        Vector2i origin;
        int16_t strength = 0;
        uint16_t radius = 0;
        PhysicalFieldKind kind = PhysicalFieldKind::MAGNETIC;
        uint8_t flags = 0;
    };
    static_assert(sizeof(PhysicalFieldSource) == 16);

    struct PermeabilityRule {
        uint16_t allowed_material_mask = 0;
        uint16_t blocked_material_mask = 0;
        uint16_t minimum_provenance = 0;
        uint16_t maximum_provenance = 65535;
        uint16_t signature_mask = 0;
        uint16_t signature_value = 0;
        uint8_t minimum_grain_class = 0;
        uint8_t maximum_grain_class = 255;
        uint8_t flags = 0;
        uint8_t reserved = 0;
    };
    static_assert(sizeof(PermeabilityRule) == 16);

    struct NativeHeatSource {
        Rect2i region;
        int32_t heat_rate = 0;
        int32_t attenuation_per_row = 0;
        int32_t minimum_heat = 0;
        int32_t target_mode = 1; // 1 transportable matter; future modes may target structures/fluids.
        bool enabled = true;
    };

    enum class MatterPhase : uint8_t { EMPTY = 0, SOLID = 1, GRANULAR = 2, LIQUID = 3, GAS = 4, MOLTEN = 5 };

    struct ThermalMaterialDefinition {
        uint16_t conductivity = 0;
        uint16_t specific_heat = 1;
        uint16_t density = 0;
        uint16_t transition_low = 0;
        uint16_t transition_high = TEMPERATURE_MAX;
        uint16_t latent_low = 0;
        uint16_t latent_high = 0;
        int16_t lower_phase = -1;
        int16_t upper_phase = -1;
        uint8_t family = 0;
        MatterPhase phase = MatterPhase::SOLID;
        uint8_t mobility = 0;
        bool amount_weighted = false;
        bool pipe_compatible = false;
    };

    struct MaterialPacket {
        uint16_t material = 0;
        uint16_t temperature = TEMPERATURE_AMBIENT;
        uint16_t provenance = 0;
        uint16_t mineral_signature = 0;
        bool occupied() const { return material != 0; }
    };
    static_assert(sizeof(MaterialPacket) == 8);

    enum class LinkedTransportKind : uint8_t { SUBSURFACE = 0, PORTAL_FUTURE = 1 };
    enum class LinkedEndpointRole : uint8_t { ENTRANCE = 0, EXIT = 1 };

    struct LinkedTransportEndpoint {
        uint64_t id = 0;
        uint64_t linked_transport_id = 0;
        Vector2i cell;
        Vector2i direction;
        LinkedTransportKind kind = LinkedTransportKind::SUBSURFACE;
        uint8_t channel = 0;
        LinkedEndpointRole role = LinkedEndpointRole::ENTRANCE;
        uint8_t flags = 0;
    };
    static_assert(sizeof(LinkedTransportEndpoint) == 40);

    struct LinkedTransportRun {
        uint64_t id = 0;
        Vector2i entrance;
        Vector2i exit;
        Vector2i direction;
        uint8_t depth = 0;
        std::vector<MaterialPacket> lane;
        LinkedTransportEndpoint entrance_endpoint;
        LinkedTransportEndpoint exit_endpoint;
    };

    struct ProductionBucket {
        int64_t second = -1;
        std::array<int64_t, MATERIAL_COUNT> produced{};
        std::array<int64_t, MATERIAL_COUNT> consumed{};
        std::array<int64_t, 6> flows{};
    };

    enum class ProductionFlowKind : uint8_t {
        WATER_WORLD_TO_PIPE = 0,
        WATER_PIPE_TO_WORLD = 1,
        PIPE_THROUGHPUT = 2,
        WET_PROCESSING_THROUGHPUT = 3,
        RESEARCH_BANK_DEPOSIT = 4,
        STEAM_PIPE_THROUGHPUT = 5,
    };

    // Dense fixed-width record allocated only for pipe-bearing structure cells.
    // One pipe mass unit equals one open-world Water mass unit.
    struct PipeSegment {
        uint16_t fluid_type = 0;
        uint16_t mass = 0;
        uint16_t temperature = TEMPERATURE_AMBIENT;
        uint16_t pressure = 0;
        int16_t last_flow = 0;
        uint16_t health = 1000;
        uint8_t flags = 0;
        uint8_t connection_mask = 0;
        uint8_t type_id = 0;
        uint8_t orientation = 0;
    };
    static_assert(sizeof(PipeSegment) == 16);

    enum class MechanicalMemberKind : uint8_t { SHAFT = 0, TURBINE = 1, GENERATOR = 2, FLYWHEEL = 3 };
    enum class PowerConsumerKind : uint8_t { MACHINE_DRIVE = 0, RESISTIVE_HEATER = 1, TRANSFORMER_INPUT = 2 };

    struct MechanicalMember {
        uint64_t id = 0;
        uint64_t entity_id = 0;
        uint64_t network_id = 0;
        Vector2i cell;
        int64_t inertia = 0;
        MechanicalMemberKind kind = MechanicalMemberKind::SHAFT;
    };

    struct MechanicalNetwork {
        uint64_t id = 0;
        int64_t rotational_energy = 0;
        int64_t total_inertia = 0;
        int64_t speed_millirpm = 0;
        int64_t input_energy = 0;
        int64_t requested_output = 0;
        int64_t delivered_output = 0;
        int64_t friction_loss = 0;
        std::vector<uint64_t> members;
    };

    struct TurbineRecord {
        uint64_t entity_id = 0;
        uint64_t mechanical_member_id = 0;
        Vector2i inlet;
        Vector2i exhaust;
        int32_t target_millirpm = 1800000;
        int32_t max_throttle = 1000;
        int32_t throttle = 1000;
        int32_t rated_flow = 2048;
        int32_t rated_pressure_delta = 12000;
        int32_t efficiency_permille = 720;
        int32_t state = 0;
        int64_t mass_throughput = 0;
        int64_t mechanical_output = 0;
        int64_t waste_heat = 0;
        bool enabled = true;
    };

    struct GeneratorRecord {
        uint64_t entity_id = 0;
        uint64_t mechanical_member_id = 0;
        uint64_t power_network_id = 0;
        uint64_t assigned_pole_id = 0;
        Vector2i tap;
        int32_t efficiency_permille = 900;
        int32_t rated_millirpm = 1500000;
        int64_t max_mechanical_input = 24000000;
        int64_t max_electrical_output = 21600000;
        int32_t state = 0;
        int64_t last_mechanical_input = 0;
        int64_t last_electrical_output = 0;
        int64_t waste_heat = 0;
        bool enabled = true;
    };

    struct PowerPoleRecord {
        uint64_t id = 0;
        uint64_t network_id = 0;
        Vector2i cell;
        uint16_t connection_range = 24;
        uint16_t coverage_radius = 12;
        uint8_t connection_limit = 4;
    };

    struct PowerEdgeRecord {
        uint64_t id = 0;
        uint64_t from = 0;
        uint64_t to = 0;
        uint8_t kind = 0;
    };

    struct PowerConsumerRecord {
        uint64_t id = 0;
        uint64_t entity_id = 0;
        uint64_t network_id = 0;
        uint64_t assigned_pole_id = 0;
        Vector2i tap;
        int64_t requested_rate = 0;
        int64_t delivered_rate = 0;
        int64_t progress_remainder = 0;
        uint8_t priority = 2;
        uint16_t satisfaction = 0;
        PowerConsumerKind kind = PowerConsumerKind::MACHINE_DRIVE;
        bool enabled = true;
    };

    struct AccumulatorRecord {
        uint64_t entity_id = 0;
        uint64_t network_id = 0;
        uint64_t assigned_pole_id = 0;
        Vector2i tap;
        int64_t capacity = 240000000;
        int64_t charge = 0;
        int64_t max_charge_rate = 4000000;
        int64_t max_discharge_rate = 4000000;
        int32_t charge_efficiency_permille = 940;
        int32_t discharge_efficiency_permille = 920;
        int64_t last_charge_input = 0;
        int64_t last_discharge_output = 0;
    };

    struct PowerSwitchRecord {
        uint64_t entity_id = 0;
        Vector2i side_a;
        Vector2i side_b;
        uint64_t pole_a = 0;
        uint64_t pole_b = 0;
        bool closed = true;
    };

    struct TransformerRecord {
        uint64_t entity_id = 0;
        Vector2i input_tap;
        Vector2i output_tap;
        uint64_t input_network_id = 0;
        uint64_t output_network_id = 0;
        int64_t max_transfer_rate = 6000000;
        int32_t efficiency_permille = 960;
        int64_t last_input = 0;
        int64_t last_output = 0;
        bool enabled = true;
    };

    struct PowerNetwork {
        uint64_t id = 0;
        std::vector<uint64_t> poles;
        std::array<int64_t, 4> demand{{0, 0, 0, 0}};
        std::array<uint16_t, 4> satisfaction{{0, 0, 0, 0}};
        int64_t generation_available = 0;
        int64_t generation_delivered = 0;
        int64_t demand_total = 0;
        int64_t delivered_total = 0;
        int64_t surplus = 0;
        int64_t storage_charge = 0;
        int64_t storage_capacity = 0;
        int64_t storage_input = 0;
        int64_t storage_output = 0;
    };

    struct ResearchDefinition {
        const char *id;
        const char *display_name;
        const char *description;
        std::vector<const char *> prerequisites;
        int64_t glass_cost;
        int64_t iron_cost;
        int64_t gold_cost;
        const char *effect;
        int32_t tree_x;
        int32_t tree_y;
    };

    struct AutomationDefinition {
        int32_t type_id;
        const char *stable_id;
        const char *display_name;
        const char *unlock_key;
        int32_t input_count;
        int32_t output_count;
        bool sensor;
        bool actuator;
        bool stateful;
    };

    struct AutomationComponent {
        uint64_t id = 0;
        int32_t type_id = 0;
        Vector2i position;
        int32_t orientation = 0;
        std::array<int32_t, 2> inputs{{0, 0}};
        int32_t output = 0;
        int32_t next_output = 0;
        int32_t mode = 0;
        int32_t material_id = 0;
        Vector2i probe_size{1, 1};
        int32_t threshold = 0;
        int32_t compare_op = 0;
        int32_t period_ticks = 30;
        int32_t on_ticks = 1;
        int32_t timer_remaining = 0;
        int32_t previous_sample = 0;
        bool pulse_pending = false;
        bool stored_state = false;
        bool manual_state = false;
        Vector2i target_position;
        uint64_t target_machine_id = 0;
        bool target_connected = false;
        bool gate_desired_open = false;
        bool gate_actual_open = false;
        bool gate_close_blocked = false;
        std::vector<uint64_t> watched_cells;
    };

    struct AutomationConnection {
        uint64_t id = 0;
        uint64_t source_component = 0;
        uint8_t source_port = 0;
        uint64_t target_component = 0;
        uint8_t target_port = 0;
    };

    struct WorldSettings {
        int32_t width = 16384;
        int32_t depth = 4096;
        int32_t sky = 512;
        int32_t surface_baseline = 0;
        int32_t surface_amplitude = 72;
        int32_t sediment_depth = 18;
        double cave_density = 0.52;
        double coal_frequency = 0.73;
        double water_frequency = 0.72;
        int32_t geology_scale = 512;
        int32_t generation_version = 1;
    };

    struct MacroSample {
        int16_t surface_elevation = 0;
        uint16_t sediment_depth = 18;
        uint16_t cave_tendency = 0;
        uint16_t water_table = 0;
        uint16_t aquifer_strength = 0;
        uint16_t geology_province = 0;
        uint16_t thermal_tendency = 0;
        uint16_t feature_density = 0;
    };

    struct VisibilityChunk {
        int64_t owner_id = 0;
        Vector2i coordinate;
        std::array<uint8_t, CELLS_PER_CHUNK / 8> discovered{};
        std::array<uint8_t, CELLS_PER_CHUNK / 8> live{};
        std::array<uint8_t, CELLS_PER_CHUNK> last_known_material{};
    };

    struct GenerationTask {
        Vector2i coordinate;
        int32_t priority = 1;
        uint64_t sequence = 0;
    };

    struct GeneratedChunk {
        Vector2i coordinate;
        std::array<uint16_t, CELLS_PER_CHUNK> material{};
        std::array<uint16_t, CELLS_PER_CHUNK> temperature{};
        std::array<uint16_t, CELLS_PER_CHUNK> provenance{};
        std::array<uint16_t, CELLS_PER_CHUNK> mineral_signature{};
        std::array<uint8_t, CELLS_PER_CHUNK> structure{};
        std::unique_ptr<std::array<uint8_t, CELLS_PER_CHUNK>> organic_moisture;
        int64_t generation_usec = 0;
    };

    enum class OrganicReactionState : uint8_t { NONE = 0, DRYING = 1, BURNING = 2, PYROLYZING = 3, COOKING = 4, BURNING_FOOD = 5 };

    struct OrganicMaterialDefinition {
        uint16_t density = 0;
        uint16_t conductivity = 0;
        uint16_t specific_heat = 1;
        uint16_t ignition_temperature = TEMPERATURE_MAX;
        uint16_t pyrolysis_temperature = TEMPERATURE_MAX;
        uint32_t combustion_heat = 0;
        uint8_t flammability = 0;
        uint8_t moisture_capacity = 0;
        uint8_t char_yield = 0;
        uint8_t ash_yield = 0;
        uint8_t smoke_yield = 0;
        uint8_t burn_rate = 0;
        bool reactive = false;
    };

    struct FellableClusterCell {
        int16_t x = 0;
        int16_t y = 0;
        uint16_t material = 0;
        uint16_t temperature = 1172;
        uint8_t amount = 255;
        uint8_t moisture = 0;
    };

    struct FellableCluster {
        uint64_t id = 0;
        Vector2i origin_q10;
        Vector2i velocity_q10;
        int32_t angle_q16 = 0;
        int32_t angular_velocity_q16 = 0;
        int8_t fall_direction = 1;
        uint8_t collision_count = 0;
        uint8_t state = 1;
        std::vector<FellableClusterCell> cells;
    };

    using ConstituentMass = std::array<int64_t, CONSTITUENT_COUNT>;

    struct FractionalMassLedger {
        uint64_t id = 0;
        std::array<ConstituentMass, 4> pending{};
        std::array<int32_t, 4> output_material{{0, 0, 0, 0}};
        std::array<int64_t, 4> emitted_channel_micro_mass{{0, 0, 0, 0}};
        int64_t input_micro_mass = 0;
        int64_t emitted_micro_mass = 0;
        int64_t queued_micro_mass = 0;
        bool has_contents() const {
            for (const ConstituentMass &channel : pending)
                for (const int64_t mass : channel) if (mass != 0) return true;
            return queued_micro_mass != 0;
        }
    };

    struct StructurePhysicalProperties {
        int32_t permeability = 0;
        int32_t aperture = 0;
        int32_t conductivity = 0;
        int32_t heat_capacity = 0;
        int32_t maximum_temperature = TEMPERATURE_MAX;
        int32_t magnetic_strength = 0;
        bool solid = true;
        bool gas_permeable = false;
    };

    int64_t seed_ = 1;
    int64_t tick_index_ = 0;
    int32_t worker_count_ = 1;
    int64_t last_movements_ = 0;
    int64_t last_cells_visited_ = 0;
    int64_t last_cells_skipped_ = 0;
    int32_t last_active_rectangles_ = 0;
    int64_t last_dirty_render_pixels_ = 0;
    int64_t last_render_upload_pixels_ = 0;
    int64_t last_granular_usec_ = 0;
    int64_t last_granular_barrier_usec_ = 0;
    int64_t last_fluid_usec_ = 0;
    int64_t last_fluid_barrier_usec_ = 0;
    int64_t last_fluid_cells_active_ = 0;
    int64_t last_fluid_cells_visited_ = 0;
    int64_t last_fluid_transfers_ = 0;
    int64_t last_fluid_mass_transferred_ = 0;
    int64_t last_fluid_downward_ = 0;
    int64_t last_fluid_lateral_ = 0;
    int64_t last_fluid_displacements_ = 0;
    int64_t last_fluid_blocked_ = 0;
    int64_t last_fluid_wake_transitions_ = 0;
    int64_t last_fluid_sleep_transitions_ = 0;
    int64_t last_fluid_border_crossings_ = 0;
    int64_t last_matter_commit_usec_ = 0;
    int32_t last_simulation_workers_used_ = 0;
    uint64_t fluid_render_revision_ = 0;
    std::unique_ptr<koalasand_core::ThermalPrototype> thermal_candidate_;
    Dictionary thermal_candidate_statistics_;
    int64_t last_thermal_active_ = 0;
    std::atomic<int64_t> last_thermal_visited_{0};
    std::atomic<int64_t> last_thermal_exchanges_{0};
    std::atomic<int64_t> last_thermal_energy_moved_{0};
    int64_t last_thermal_source_energy_ = 0;
    std::atomic<int64_t> last_phase_changes_{0};
    int64_t last_thermal_usec_ = 0;
    int64_t last_thermal_barrier_usec_ = 0;
    int32_t last_thermal_workers_used_ = 0;
    std::atomic<int64_t> total_phase_changes_{0};
    int64_t total_thermal_source_energy_ = 0;
    int64_t thermal_rounding_reservoir_ = 0;
    int64_t last_gas_active_ = 0;
    int64_t last_gas_visited_ = 0;
    int64_t last_gas_transfers_ = 0;
    int64_t last_gas_mass_transferred_ = 0;
    int64_t last_gas_usec_ = 0;
    int64_t last_fluid_schedule_usec_ = 0;
    int64_t last_fluid_traversal_usec_ = 0;
    int64_t last_fluid_commit_profile_usec_ = 0;
    int64_t last_fluid_settle_usec_ = 0;
    int64_t last_gas_vertical_attempts_ = 0;
    int64_t last_gas_diagonal_attempts_ = 0;
    int64_t last_gas_lateral_attempts_ = 0;
    int64_t last_gas_local_transfers_ = 0;
    int64_t last_gas_cross_chunk_transfers_ = 0;
    std::array<int64_t, 8> last_fluid_worker_jobs_{};
    std::array<int64_t, 8> last_fluid_worker_cells_{};
    std::array<int64_t, 8> last_fluid_worker_usec_{};
    std::atomic<int64_t> total_steam_generated_{0};
    std::atomic<int64_t> total_steam_condensed_{0};
    std::unordered_set<uint64_t> thermal_switch_cells_;
    std::unordered_set<uint64_t> closed_thermal_switches_;
    std::unordered_set<uint64_t> heat_exchanger_cells_;
    std::mutex thermal_notification_mutex_;

    std::unordered_map<uint64_t, std::unique_ptr<Chunk>> chunks_;
    std::vector<std::thread> render_workers_;
    std::vector<std::pair<Chunk *, Bounds>> render_jobs_;
    std::atomic<size_t> render_job_index_{0};
    std::atomic<int32_t> render_workers_used_current_{0};
    std::mutex render_mutex_;
    std::condition_variable render_start_;
    std::condition_variable render_done_;
    std::condition_variable render_ready_;
    uint64_t render_generation_ = 0;
    size_t render_workers_pending_ = 0;
    size_t render_workers_ready_ = 0;
    bool render_stop_ = false;
    int32_t last_render_workers_used_ = 0;
    std::unique_ptr<koalasand_core::ParallelExecutor> simulation_executor_;
    bool world_generation_enabled_ = false;
    WorldSettings world_settings_;

    std::vector<std::thread> generation_workers_;
    mutable std::mutex generation_mutex_;
    std::condition_variable generation_start_;
    std::condition_variable generation_idle_;
    std::vector<GenerationTask> generation_queue_;
    std::unordered_set<uint64_t> generating_keys_;
    std::unordered_set<uint64_t> queued_keys_;
    std::unordered_set<uint64_t> completed_keys_;
    std::deque<std::unique_ptr<GeneratedChunk>> completed_generation_;
    std::vector<Vector2i> evicted_chunks_;
    bool generation_stop_ = false;
    uint64_t generation_sequence_ = 0;
    int32_t generation_worker_count_ = 0;
    int32_t last_chunks_published_ = 0;
    int64_t last_publish_usec_ = 0;
    int64_t total_generation_usec_ = 0;
    int64_t worst_generation_usec_ = 0;
    int64_t total_chunks_generated_ = 0;
    int64_t total_chunks_published_ = 0;
    int64_t total_chunks_evicted_ = 0;
    int32_t peak_generation_queue_ = 0;
    int32_t peak_allocated_chunks_ = 0;
    std::unordered_map<uint64_t, VisibilityChunk> visibility_chunks_;
    std::unordered_map<int64_t, std::vector<uint64_t>> visibility_owner_chunks_;
    std::unordered_map<int64_t, std::vector<uint64_t>> visibility_live_chunks_;
    int64_t visibility_revision_ = 0;
    int64_t last_visibility_usec_ = 0;
    int64_t last_visibility_cells_sampled_ = 0;
    int64_t last_visibility_cells_live_ = 0;
    int64_t last_visibility_cells_discovered_ = 0;
    int64_t last_collision_usec_ = 0;
    int64_t last_collision_cells_sampled_ = 0;

    uint64_t next_machine_id_ = 1;
    uint64_t structure_revision_ = 0;
    uint64_t machine_visual_revision_ = 0;
    std::unordered_map<uint64_t, MachineEntity> machine_entities_;
    std::unordered_set<uint64_t> active_belts_;
    std::unordered_set<uint64_t> active_machines_;
    std::unordered_map<uint64_t, std::vector<uint64_t>> machine_port_watchers_;
    std::vector<Vector2i> dirty_structure_chunks_;
    int64_t structures_allocated_ = 0;
    int64_t belts_total_ = 0;
    int64_t last_belts_active_ = 0;
    int64_t last_belts_considered_ = 0;
    int64_t last_belts_skipped_ = 0;
    int64_t last_belt_moves_ = 0;
    int64_t last_blocked_belt_attempts_ = 0;
    int64_t last_logistics_usec_ = 0;
    int64_t last_machines_active_ = 0;
    int64_t last_machines_visited_ = 0;
    int64_t last_machine_inputs_ = 0;
    int64_t last_machine_outputs_ = 0;
    int64_t last_machine_blocked_ = 0;
    int64_t last_fuel_starved_ = 0;
    int64_t last_machine_usec_ = 0;
    int64_t total_sieve_processed_ = 0;
    int64_t total_magnetic_processed_ = 0;
    int64_t total_furnace_processed_ = 0;
    int64_t total_glass_ = 0;
    int64_t total_iron_ = 0;
    int64_t total_gold_ = 0;
    int64_t total_residue_ = 0;
    int64_t total_ash_ = 0;
    uint64_t next_linked_transport_id_ = 1;
    std::unordered_map<uint64_t, LinkedTransportRun> linked_transports_;
    std::array<std::unordered_map<uint64_t, uint64_t>, 3> subsurface_occupancy_;
    std::unordered_map<uint64_t, uint64_t> subsurface_endpoint_channels_;
    std::unordered_map<uint64_t, std::vector<uint64_t>> subsurface_cell_watchers_;
    std::unordered_set<uint64_t> active_linked_transports_;
    uint64_t subsurface_revision_ = 0;
    int64_t last_subsurface_active_ = 0;
    int64_t last_subsurface_visited_ = 0;
    int64_t last_subsurface_moves_ = 0;
    int64_t last_subsurface_blocked_ = 0;
    int64_t last_subsurface_usec_ = 0;
    int64_t total_subsurface_moves_ = 0;
    std::vector<ProductionBucket> production_buckets_;
    std::array<int64_t, MATERIAL_COUNT> production_lifetime_produced_{};
    std::array<int64_t, MATERIAL_COUNT> production_lifetime_consumed_{};
    std::array<int64_t, 6> production_lifetime_flows_{};
    int64_t production_events_total_ = 0;
    std::unordered_map<uint64_t, PhysicalProcessor> physical_processors_;
    std::unordered_map<uint64_t, std::vector<uint64_t>> physical_chunk_watchers_;
    std::unordered_set<uint64_t> active_magnets_;
    std::unordered_set<uint64_t> active_screens_;
    std::unordered_set<uint64_t> active_heaters_;
    std::unordered_set<uint64_t> active_wet_sluices_;
    int64_t last_magnets_active_ = 0;
    int64_t last_magnetic_cells_tested_ = 0;
    int64_t last_magnetic_moves_ = 0;
    int64_t last_magnetic_usec_ = 0;
    int64_t last_screens_active_ = 0;
    int64_t last_screen_grains_tested_ = 0;
    int64_t last_screen_vibration_evaluations_ = 0;
    int64_t last_screen_passes_ = 0;
    int64_t last_screen_usec_ = 0;
    int64_t total_magnetic_moves_ = 0;
    int64_t total_screen_passes_ = 0;
    int64_t last_heaters_active_ = 0;
    int64_t last_heated_cells_ = 0;
    int64_t last_heat_reactions_ = 0;
    int64_t last_heat_usec_ = 0;
    int64_t total_heat_reactions_ = 0;
    std::unordered_map<uint64_t, PipeSegment> pipe_segments_;
    std::unordered_map<uint64_t, int64_t> pipe_phase_energy_;
    std::unordered_set<uint64_t> active_pipe_segments_;
    std::vector<uint64_t> active_pipe_sorted_cache_;
    std::vector<PipeSegment *> active_pipe_record_cache_;
    std::vector<uint64_t> pipe_next_active_buffer_;
    std::vector<uint64_t> pipe_candidate_active_buffer_;
    std::vector<uint64_t> pipe_filtered_active_buffer_;
    std::vector<uint8_t> pipe_keep_active_buffer_;
    bool active_pipe_cache_dirty_ = true;
    uint64_t pipe_revision_ = 0;
    int64_t last_pipe_active_ = 0;
    int64_t last_pipe_visited_ = 0;
    int64_t last_pipe_transfers_ = 0;
    int64_t last_pipe_mass_transferred_ = 0;
    int64_t last_pipe_pump_work_ = 0;
    int64_t last_pipe_valve_work_ = 0;
    int64_t last_pipe_intake_mass_ = 0;
    int64_t last_pipe_outlet_mass_ = 0;
    int64_t last_pipe_leak_mass_ = 0;
    int64_t last_pipe_breaches_ = 0;
    int64_t last_pipe_usec_ = 0;
    int64_t last_pipe_gather_usec_ = 0;
    int64_t last_pipe_state_usec_ = 0;
    int64_t last_pipe_flow_usec_ = 0;
    int64_t last_pipe_schedule_usec_ = 0;
    int64_t last_pipe_pressure_edges_ = 0;
    int64_t last_pipe_damage_checks_ = 0;
    int64_t last_pipe_phase_checks_ = 0;
    int64_t last_pipe_heat_edges_ = 0;
    int64_t last_pipe_automation_hooks_ = 0;
    int64_t total_pipe_leak_mass_ = 0;
    int64_t last_wet_cells_visited_ = 0;
    int64_t last_wet_grains_moved_ = 0;
    int64_t last_wet_heavy_captured_ = 0;
    int64_t last_wet_light_output_ = 0;
    int64_t last_wet_usec_ = 0;
    static constexpr int32_t PROGRESSION_SCHEMA_VERSION = 1;
    int32_t game_mode_ = 0;
    int64_t bank_glass_ = 0;
    int64_t bank_iron_ = 0;
    int64_t bank_gold_ = 0;
    std::unordered_set<std::string> unlocked_research_;
    uint64_t progression_revision_ = 0;
    int64_t last_banks_active_ = 0;
    int64_t last_banks_visited_ = 0;
    int64_t last_bank_accepted_ = 0;
    int64_t last_bank_rejected_ = 0;
    int64_t last_bank_blocked_ = 0;
    int64_t last_bank_usec_ = 0;
    int64_t total_bank_accepted_ = 0;
    int64_t total_bank_rejected_ = 0;
    static constexpr int32_t AUTOMATION_SCHEMA_VERSION = 1;
    uint64_t next_automation_component_id_ = 1;
    uint64_t next_automation_connection_id_ = 1;
    uint64_t automation_revision_ = 0;
    std::unordered_map<uint64_t, AutomationComponent> automation_components_;
    std::unordered_map<uint64_t, AutomationConnection> automation_connections_;
    std::unordered_map<uint64_t, std::vector<uint64_t>> automation_outgoing_;
    std::unordered_map<uint64_t, uint64_t> automation_input_sources_;
    std::unordered_map<uint64_t, std::vector<uint64_t>> automation_cell_watchers_;
    std::unordered_map<uint64_t, std::vector<uint64_t>> automation_machine_watchers_;
    std::unordered_set<uint64_t> automation_dirty_;
    std::unordered_set<uint64_t> automation_scheduled_;
    std::unordered_map<uint64_t, bool> controlled_belts_;
    std::unordered_set<uint64_t> open_gate_cells_;
    std::unordered_set<uint64_t> blocked_gate_components_;
    int64_t last_automation_awake_ = 0;
    int64_t last_automation_signals_changed_ = 0;
    int64_t last_automation_sensor_evaluations_ = 0;
    int64_t last_automation_logic_evaluations_ = 0;
    int64_t last_automation_actuator_changes_ = 0;
    int64_t last_automation_usec_ = 0;
    int64_t last_automation_topology_usec_ = 0;

    static constexpr int32_t POWER_SCHEMA_VERSION = 1;
    std::unordered_map<uint64_t, MechanicalMember> mechanical_members_;
    std::unordered_map<uint64_t, MechanicalNetwork> mechanical_networks_;
    std::unordered_map<uint64_t, TurbineRecord> turbines_;
    std::unordered_map<uint64_t, GeneratorRecord> generators_;
    std::unordered_map<uint64_t, PowerPoleRecord> power_poles_;
    std::unordered_map<uint64_t, PowerEdgeRecord> power_edges_;
    std::unordered_map<uint64_t, PowerConsumerRecord> power_consumers_;
    std::unordered_set<uint64_t> resistive_heater_consumers_;
    std::unordered_map<uint64_t, AccumulatorRecord> accumulators_;
    std::unordered_map<uint64_t, PowerSwitchRecord> power_switches_;
    std::unordered_map<uint64_t, TransformerRecord> transformers_;
    std::unordered_map<uint64_t, PowerNetwork> power_networks_;
    std::unordered_map<uint64_t, uint64_t> power_entity_to_consumer_;
    bool mechanical_topology_dirty_ = false;
    bool electrical_topology_dirty_ = false;
    uint64_t mechanical_revision_ = 0;
    uint64_t power_revision_ = 0;
    int64_t last_mechanical_usec_ = 0;
    int64_t last_power_usec_ = 0;
    int64_t last_power_topology_usec_ = 0;
    int64_t last_mechanical_topology_usec_ = 0;
    int64_t last_mechanical_active_networks_ = 0;
    int64_t last_power_active_networks_ = 0;
    int64_t thermal_energy_into_turbines_ = 0;
    int64_t mechanical_energy_produced_ = 0;
    int64_t turbine_losses_ = 0;
    int64_t mechanical_energy_consumed_ = 0;
    int64_t electrical_energy_produced_ = 0;
    int64_t electrical_energy_consumed_ = 0;
    int64_t electrical_energy_stored_ = 0;
    int64_t electrical_energy_discharged_ = 0;
    int64_t generator_losses_ = 0;
    int64_t storage_losses_ = 0;

    uint64_t next_fellable_cluster_id_ = 1;
    std::unordered_map<uint64_t, FellableCluster> fellable_clusters_;
    std::unordered_set<uint64_t> reactive_cells_;
    std::unordered_set<uint64_t> disturbed_atmosphere_chunks_;
    uint64_t organic_revision_ = 0;
    int64_t last_cluster_usec_ = 0;
    int64_t last_cluster_collision_samples_ = 0;
    int64_t last_atmosphere_usec_ = 0;
    int64_t last_atmosphere_cells_ = 0;
    int64_t last_reaction_usec_ = 0;
    int64_t last_reaction_cells_ = 0;
    int64_t total_trees_felled_ = 0;
    int64_t total_wood_produced_ = 0;
    int64_t total_wood_burned_ = 0;
    int64_t total_wood_pyrolyzed_ = 0;
    int64_t total_charcoal_produced_ = 0;
    int64_t total_charcoal_burned_ = 0;
    int64_t total_organic_ash_produced_ = 0;
    int64_t total_smoke_produced_ = 0;
    int64_t total_organic_ash_micro_mass_ = 0;
    int64_t total_smoke_micro_mass_ = 0;
    int64_t total_charcoal_micro_mass_ = 0;
    int64_t total_wood_water_evaporated_ = 0;
    int64_t total_food_cooked_ = 0;
    int64_t total_food_burned_ = 0;
    int64_t total_combustion_energy_ = 0;
    int64_t total_oxygen_consumed_ = 0;
    std::unordered_map<uint64_t, FractionalMassLedger> fractional_ledgers_;
    std::unordered_map<uint16_t, ConstituentMass> explicit_compositions_;
    uint16_t next_explicit_composition_id_ = 1;
    int64_t conservation_input_micro_mass_ = 0;
    int64_t conservation_output_micro_mass_ = 0;
    int64_t conservation_rejected_removals_ = 0;
    uint16_t milestone_flags_ = 0;
    std::unordered_set<uint64_t> component_processing_cells_;
    std::unordered_set<uint64_t> thermal_component_cells_;

    static int32_t floor_div(int32_t value, int32_t divisor);
    static bool checked_rect_end(Rect2i area, int64_t maximum_cells, Vector2i &end);
    static bool has_neighbor_margin(Vector2i cell, int32_t margin);
    static Vector2i world_to_chunk(Vector2i world_cell);
    static Vector2i world_to_local(Vector2i world_cell);
    static uint64_t chunk_key(Vector2i coordinate);
    static int32_t local_index(Vector2i local);
    static uint32_t hash_2d(int64_t seed, Vector2i position, int32_t salt = 0);
    static uint32_t mix_int(uint32_t hash, int32_t component);
    static uint64_t cell_key(Vector2i world_cell);
    static Vector2i cell_from_key(uint64_t key);

    Chunk *get_chunk(Vector2i coordinate);
    const Chunk *get_chunk(Vector2i coordinate) const;
    Chunk *get_or_create_chunk(Vector2i coordinate);
    std::vector<Chunk *> sorted_chunks();
    std::vector<const Chunk *> sorted_chunks() const;

    struct MatterJobResult {
        int64_t active = 0;
        int64_t visited = 0;
        int64_t moved = 0;
        int64_t transfers = 0;
        int64_t mass_transferred = 0;
        int64_t downward = 0;
        int64_t lateral = 0;
        int64_t displaced = 0;
        int64_t blocked = 0;
        int64_t border = 0;
        int64_t screen_passes = 0;
        int64_t gas_active = 0;
        int64_t gas_visited = 0;
        int64_t gas_transfers = 0;
        int64_t gas_mass_transferred = 0;
        int64_t gas_vertical_attempts = 0;
        int64_t gas_diagonal_attempts = 0;
        int64_t gas_lateral_attempts = 0;
        int64_t gas_local_transfers = 0;
        int64_t gas_cross_chunk_transfers = 0;
        int64_t work_usec = 0;
        int32_t worker_index = 0;
        int64_t enthalpy_rounding = 0;
        std::vector<Vector2i> changed_cells;
    };

    struct ThermalJobResult {
        int64_t visited = 0;
        int64_t exchanges = 0;
        int64_t energy_moved = 0;
        int64_t phase_changes = 0;
        int64_t enthalpy_rounding = 0;
    };

    void activate_world_cell(Vector2i world_cell, int32_t radius = 1);
    void include_next_world_cell(Vector2i world_cell, int32_t radius = 1);
    void mark_render_world_cell(Vector2i world_cell, int32_t radius = 1);
    bool move_if_empty(Vector2i source, Vector2i destination);
    bool move_granular_fast(Chunk &source_chunk, int32_t source_index, Vector2i source, Vector2i destination,
                            MatterJobResult &result, bool collect_changes);
    bool displace_water_for_sand(Vector2i destination, MatterJobResult &result, bool collect_changes);
    void process_granular_parallel(const std::vector<Chunk *> &active_chunks);
    void process_granular_chunk(Chunk &chunk, const Bounds &bounds, MatterJobResult &result, bool collect_changes);
    void process_fluid_parallel();
    void process_fluid_chunk(Chunk &chunk, const FluidActivity &activity, MatterJobResult &result, bool collect_changes);
    void apply_matter_notifications(const std::vector<MatterJobResult> &results);
    bool fluid_destination_available(Vector2i cell) const;
    int32_t water_mass_at(const Chunk &chunk, int32_t index) const;
    int32_t water_mass_at(Vector2i cell) const;
    int32_t material_amount_at(const Chunk &chunk, int32_t index) const;
    int32_t material_amount_at(Vector2i cell) const;
    void ensure_liquid_plane(Chunk &chunk);
    void ensure_phase_energy_plane(Chunk &chunk);
    void write_mobile_state(Vector2i cell, int32_t material, int32_t amount, uint16_t temperature,
                            uint16_t provenance, uint16_t signature, MatterJobResult *result = nullptr,
                            bool collect_changes = false);
    int32_t transfer_mobile_material(Vector2i source, Vector2i destination, int32_t requested,
                                     MatterJobResult &result, bool primary_direction, bool collect_changes);
    int32_t transfer_mobile_material_indexed(Chunk &source_chunk, int32_t source_index, Vector2i source,
                                             Chunk &destination_chunk, int32_t destination_index, Vector2i destination,
                                             int32_t requested, MatterJobResult &result, bool primary_direction,
                                             bool collect_changes);
    bool mobile_destination_available(Vector2i cell, int32_t material) const;
    static bool is_mobile_material(int32_t material);
    static bool is_gas_material(int32_t material);
    static bool is_liquid_material(int32_t material);
    void write_water_state(Vector2i cell, int32_t mass, uint16_t temperature, MatterJobResult *result = nullptr,
                           bool collect_changes = false);
    int32_t transfer_water(Vector2i source, Vector2i destination, int32_t requested, MatterJobResult &result,
                           bool downward, bool collect_changes);
    void activate_fluid_world_cell(Vector2i world_cell, int32_t radius = 1);
    void include_next_fluid_world_cell(Vector2i world_cell, int32_t radius = 1);
    void refresh_fluid_activity(Chunk &chunk);
    void release_redundant_liquid_planes();
    void process_thermodynamics();
    void process_thermal_structures();
    void compute_thermal_chunk(Chunk &chunk, const FluidActivity &activity, ThermalJobResult &result);
    void commit_thermal_chunk(Chunk &chunk, const FluidActivity &activity, ThermalJobResult &result);
    void activate_thermal_world_cell(Vector2i world_cell, int32_t radius = 1);
    void include_next_thermal_world_cell(Vector2i world_cell, int32_t radius = 1);
    void release_redundant_phase_planes();
    int32_t thermal_capacity(int32_t material, int32_t amount) const;
    int64_t cell_enthalpy(const Chunk &chunk, int32_t index) const;
    void set_cell_enthalpy(Vector2i cell, int64_t enthalpy, int32_t preferred_material = -1);
    void add_cell_energy(Vector2i cell, int64_t energy);
    static const std::array<ThermalMaterialDefinition, MATERIAL_COUNT> &thermal_material_definitions();
    static int64_t phase_base_enthalpy(int32_t material, int32_t amount);
    bool should_collect_matter_changes() const;
    bool can_material_enter(Vector2i source, Vector2i destination) const;
    bool magnetic_capture_supports(Vector2i world_cell) const;
    bool is_permeable_screen_cell(Vector2i world_cell) const;
    Vector2i choose_destination(Vector2i source) const;
    bool is_empty_for_material(Vector2i world_cell) const;
    bool is_structure_solid(Vector2i world_cell) const;
    bool material_transportable(int32_t material_id) const;
    bool permeability_allows(const PermeabilityRule &rule, int32_t material_id, int32_t provenance, uint16_t signature) const;
    static const PermeabilityRule &fine_screen_permeability_rule();
    void reset_production_statistics();
    void record_production_event(int32_t material_id, int64_t amount, bool produced);
    void record_production_flow(ProductionFlowKind kind, int64_t amount);
    bool moved_this_tick(Vector2i world_cell) const;
    void mark_moved_this_tick(Vector2i world_cell);
    void clear_movement_flags(const std::vector<Chunk *> &active_chunks);
    void activate_belts_near(Vector2i material_cell);
    void process_conveyors();
    void reset_subsurface_logistics();
    void process_subsurface_logistics();
    void wake_subsurface_at(Vector2i world_cell);
    bool subsurface_unlocked(int32_t depth) const;
    void activate_machines_at_port(Vector2i world_cell);
    void register_machine_ports(const MachineEntity &entity);
    void unregister_machine_ports(const MachineEntity &entity);
    void process_machines();
    void register_physical_processor(const MachineEntity &entity);
    void unregister_physical_processor(uint64_t entity_id);
    void activate_physical_near(Vector2i world_cell);
    void process_physical_fields();
    void process_vibrating_screens();
    void process_physical_heaters();
    void apply_heat_source(const NativeHeatSource &source);
    void process_wet_sluices();
    int32_t grain_size_class(int32_t material_id, int32_t profile_id, uint16_t signature) const;
    int32_t magnetic_susceptibility(int32_t material_id, int32_t profile_id, uint16_t signature) const;
    bool physical_region_has_material(const PhysicalProcessor &processor) const;
    static bool is_physical_processor(int32_t type_id);
    bool take_cell(Vector2i world_cell, uint16_t &material, uint16_t &provenance, uint16_t &signature);
    bool emit_cell(Vector2i world_cell, uint16_t material, uint16_t provenance, uint16_t signature);
    Vector2i transform_local(const StructureDefinition &definition, Vector2i local, int32_t orientation) const;
    Vector2i machine_port(const MachineEntity &entity, int32_t index, bool output) const;
    static bool is_processing_machine(int32_t type_id);
    int32_t process_ticks(int32_t type_id) const;
    uint16_t mineral_signature_for(Vector2i original_cell) const;
    int32_t hidden_constituent(int32_t profile_id, uint16_t signature) const;
    int32_t processing_result(int32_t material_id, int32_t profile_id, uint16_t signature, int32_t process_id) const;
    void rebuild_render_region(Chunk &chunk, const Bounds &bounds);
    void sample_rgba(const Chunk &chunk, int32_t local_x, int32_t local_y, uint8_t *output) const;
    void configure_workers(int32_t requested_workers);
    void stop_workers();
    void render_worker_loop();
    void rebuild_render_jobs();
    bool is_inside_virtual_world(Vector2i world_cell) const;
    bool is_chunk_in_virtual_world(Vector2i coordinate) const;
    void ensure_generated_for_edit(Vector2i coordinate);
    void publish_generated_chunk(std::unique_ptr<GeneratedChunk> generated);
    void refresh_generated_activity(Chunk &chunk);
    void request_simulation_halo(const std::vector<Chunk *> &active_chunks);
    void configure_generation_workers(int32_t requested_workers);
    void stop_generation_workers();
    void generation_worker_loop();
    std::unique_ptr<GeneratedChunk> generate_chunk_data(Vector2i coordinate) const;
    std::unique_ptr<GeneratedChunk> generate_chunk_data_v2(Vector2i coordinate) const;
    MacroSample macro_sample_for(int64_t seed, Vector2i macro_coordinate) const;
    int32_t surface_height_at_v2(int32_t world_x) const;
    int32_t cave_type_at_v2(Vector2i world_cell, int32_t surface_height) const;
    bool aquifer_at_v2(Vector2i world_cell, int32_t surface_height, const MacroSample &macro) const;
    bool thermal_at_v2(Vector2i world_cell, int32_t surface_height, const MacroSample &macro) const;
    uint64_t visibility_key(int64_t owner_id, Vector2i chunk_coordinate) const;
    VisibilityChunk *visibility_chunk_for(int64_t owner_id, Vector2i chunk_coordinate, bool create);
    const VisibilityChunk *visibility_chunk_for(int64_t owner_id, Vector2i chunk_coordinate) const;
    double value_noise_1d(double x, int32_t salt) const;
    double value_noise_2d(double x, double y, int32_t salt) const;
    double fbm_2d(double x, double y, int32_t salt, int32_t octaves = 4) const;
    int32_t surface_height_at(int32_t world_x) const;
    bool cave_at(Vector2i world_cell, int32_t surface_height) const;
    bool coal_at(Vector2i world_cell, int32_t surface_height) const;
    bool water_at(Vector2i world_cell, int32_t surface_height) const;
    void apply_organic_features_to_generated(GeneratedChunk &generated) const;
    void reset_organic_physics();
    void process_organic_physics();
    void process_fellable_clusters();
    void process_atmosphere();
    void process_reactions();
    void ensure_moisture_plane(Chunk &chunk);
    void ensure_atmosphere_plane(Chunk &chunk);
    void ensure_reaction_planes(Chunk &chunk);
    void activate_reactive_cell(Vector2i world_cell);
    int32_t oxidizer_at(Vector2i world_cell) const;
    bool write_oxidizer(Vector2i world_cell, int32_t value);
    bool emit_organic_product(Vector2i source, int32_t material, int32_t amount, int32_t temperature, bool prefer_up);
    bool settle_cluster(FellableCluster &cluster);
    std::vector<Vector2i> rasterized_cluster_cells(const FellableCluster &cluster, int32_t angle_q16, Vector2i origin_q10) const;
    static const std::array<OrganicMaterialDefinition, MATERIAL_COUNT> &organic_material_definitions();
    static bool is_organic_material(int32_t material);
    static bool is_combustible_material(int32_t material);
    void reset_phase13();
    ConstituentMass composition_for(int32_t material_id, int32_t profile_id, uint16_t signature) const;
    static int64_t composition_total(const ConstituentMass &composition);
    static ConstituentMass take_quantum(ConstituentMass &source, int64_t quantum);
    void split_into_ledger(FractionalMassLedger &ledger, const ConstituentMass &input, int32_t route) const;
    Dictionary ledger_report(const FractionalMassLedger &ledger) const;
    void update_milestones();
    static const StructurePhysicalProperties &structure_physical_properties(int32_t type_id);
    bool structure_has_fractional_contents(Vector2i world_cell) const;
    void process_component_processing();
    static double smoothstep(double value);
    static double lerp_double(double from, double to, double amount);
    static uint32_t content_hash_mix(uint32_t hash, uint32_t component);
    static const std::vector<StructureDefinition> &structure_definitions();
    static const StructureDefinition *structure_definition(int32_t type_id);
    static const std::vector<ResearchDefinition> &research_definitions();
    static const ResearchDefinition *research_definition(const std::string &id);
    bool has_research(const char *id) const;
    bool structure_unlocked(int32_t type_id) const;
    int32_t conveyor_ticks_per_cell() const;
    int32_t furnace_fuel_units() const;
    std::vector<Vector2i> transformed_occupied(const StructureDefinition &definition, Vector2i origin, int32_t orientation) const;
    bool ensure_structure_chunks_generated(const std::vector<Vector2i> &cells);
    void set_structure_cell(Vector2i world_cell, uint8_t type_id);
    void clear_structure_cell(Vector2i world_cell);
    void mark_structure_chunk_dirty(Vector2i coordinate);
    void wake_after_structure_change(Vector2i world_cell);
    static bool is_pipe_structure(int32_t type_id);
    static bool is_pipe_device(int32_t type_id);
    void register_pipe_segment(Vector2i world_cell, int32_t type_id, int32_t orientation);
    bool unregister_pipe_segment(Vector2i world_cell, bool cutting);
    void wake_pipe(Vector2i world_cell);
    void wake_pipe_neighbors(Vector2i world_cell);
    void refresh_pipe_connections(Vector2i world_cell);
    bool pipe_connection_open(Vector2i from, Vector2i to) const;
    void process_pipe_fluid();
    int32_t pipe_potential(Vector2i cell, const PipeSegment &segment, Vector2i direction) const;
    int64_t pipe_enthalpy(uint64_t key, const PipeSegment &segment) const;
    int64_t pipe_heat_capacity(const PipeSegment &segment) const;
    int64_t set_pipe_enthalpy(uint64_t key, PipeSegment &segment, int64_t enthalpy, int32_t preferred_fluid);
    int32_t transfer_pipe_mass(Vector2i from, Vector2i to, int32_t requested);
    int32_t transfer_pipe_mass_indexed(uint64_t source_key, PipeSegment &source, Vector2i from,
                                       uint64_t destination_key, PipeSegment &destination, Vector2i to,
                                       int32_t requested);
    int32_t pipe_to_world(Vector2i pipe_cell, Vector2i world_cell, int32_t requested);
    int32_t world_to_pipe(Vector2i world_cell, Vector2i pipe_cell, int32_t requested);
    void update_pipe_damage(Vector2i cell, PipeSegment &segment);
    void reset_pipe_logistics();
    static const std::vector<AutomationDefinition> &automation_definitions();
    static const AutomationDefinition *automation_definition(int32_t type_id);
    static uint64_t automation_input_key(uint64_t component_id, int32_t port);
    void reset_automation();
    void rebuild_component_watchers(AutomationComponent &component);
    void unregister_component_watchers(const AutomationComponent &component);
    void notify_automation_cell_change(Vector2i world_cell);
    void notify_automation_machine_change(uint64_t machine_id);
    void process_automation();
    int32_t evaluate_automation_component(AutomationComponent &component);
    int32_t sample_material_sensor(AutomationComponent &component) const;
    int32_t sample_level_sensor(AutomationComponent &component) const;
    uint64_t machine_id_at(Vector2i world_cell) const;
    void apply_automation_actuator(AutomationComponent &component);
    bool automation_unlocked(int32_t type_id) const;
    void reset_power();
    static bool is_power_structure(int32_t type_id);
    static bool is_mechanical_structure(int32_t type_id);
    void register_power_structure(const MachineEntity &entity);
    void register_power_tile(int32_t type_id, Vector2i cell, int32_t orientation);
    void unregister_power_structure(uint64_t entity_id);
    void unregister_power_tile(int32_t type_id, Vector2i cell);
    void rebuild_mechanical_topology();
    void rebuild_electrical_topology();
    void process_power();
    void rebuild_power_aggregates();
    uint64_t nearest_power_pole(Vector2i cell, int32_t radius, uint64_t exclude = 0) const;
    uint64_t mechanical_member_id_at(Vector2i cell) const;
    int64_t mechanical_speed_for_member(uint64_t member_id) const;
    void update_mechanical_speed(MechanicalNetwork &network);
    void add_power_consumer(uint64_t id, uint64_t entity_id, Vector2i tap, int64_t request, int32_t priority, PowerConsumerKind kind);
    void remove_power_consumer(uint64_t id);
    void account_local_waste_heat(Vector2i origin, int64_t energy);
    int32_t electric_satisfaction(int32_t type_id, uint64_t entity_id, Vector2i cell) const;
};

} // namespace godot
