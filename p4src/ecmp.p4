#include "include/std_defines.p4"
#include "include/std_headers.p4"
#include "include/std_parser.p4"
#include "include/std_actions.p4"

/* ECMP machinery */
header_type ecmp_metadata_t {
    fields {
        groupId : 16;
        selector : 16;
    }
}

metadata ecmp_metadata_t ecmp_metadata;

field_list ecmp_hash_fields {
    ethernet.dstAddr;
    ethernet.srcAddr;
    ipv4.srcAddr;
    ipv4.dstAddr;
    ipv4.protocol;
    tcp.srcPort;
    tcp.dstPort;
    udp.srcPort;
    udp.dstPort;
}

field_list_calculation ecmp_hash {
    input {
        ecmp_hash_fields;
    }
    algorithm : crc32;
    output_width : 32;
}

action ecmp_group(groupId, groupSize) {
    modify_field(ecmp_metadata.groupId, groupId);
    // The modify_field_with_hash_based_offset works in this way (base + (hash_value % groupSize))
    // e.g. if we want to select a port number between 0 and 4 we use: (0 + (hash_value % 5))
    modify_field_with_hash_based_offset(ecmp_metadata.selector, 0, ecmp_hash, groupSize);
}

action count_packet() {
    count(ingress_counter, standard_metadata.ingress_port);
    count(egress_counter, standard_metadata.egress_spec);
}

/* Main table */
table table0 {
    reads {
        standard_metadata.ingress_port : ternary;
        ethernet.dstAddr : ternary;
        ethernet.srcAddr : ternary;
        ethernet.etherType : ternary;
    }
    actions {
        set_egress_port;
        ecmp_group;
        send_to_cpu;
        _drop;
    }
    support_timeout: true;
}

table ecmp_group_table {
    reads {
        ecmp_metadata.groupId : exact;
        ecmp_metadata.selector : exact;
    }
    actions {
        set_egress_port;
    }
}

table port_count {
    actions {
        count_packet;
    }
}

counter table0_counter {
    type: packets;
    direct: table0;
    min_width : 32;
}

counter ecmp_group_table_counter {
    type: packets;
    direct: ecmp_group_table;
    min_width : 32;
}


counter ingress_counter {
    type : packets; // bmv2 always counts both bytes and packets 
    instance_count : 1024;
    min_width : 32;
}

counter egress_counter {
    type: packets;
    instance_count : 1024;
    min_width : 32;
}

/* Control flow */
control ingress {
    apply(table0) {
        ecmp_group { // ecmp action was used
            apply(ecmp_group_table);
        }
    }
    
    apply(port_count);
}