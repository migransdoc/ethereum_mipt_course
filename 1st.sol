// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

contract Practice {
    struct Student {
        string name;
        uint8 age;
    }

    Student[] public students;
    string[] public groups;

    // mapping (string => Student[]) public groupToStudents;

    mapping(uint256 => string) public idStudentToGroup;
    mapping(uint256 => Student) public idToStudent;
    uint256 id = 0;

    constructor() {
        groups.push("MIPT 1");
        groups.push("MIPT 2");
        groups.push("MIPT 3");
        groups.push("MIPT 4");
        groups.push("MIPT 5");
    }

    function addStudent(string memory _name, uint8 _age) public {
        uint256 randGroup = uint256(
            keccak256(abi.encodePacked(block.difficulty, block.timestamp, _name, _age))
        ) % groups.length;

        idToStudent[id] = Student(_name, _age);
        students.push(Student(_name, _age));
        idStudentToGroup[id] = groups[randGroup];
        id++;
    }
}
