class CreateCustomer {
  String? status;
  String? message;
  Data? data;

  CreateCustomer({this.status, this.message, this.data});

  CreateCustomer.fromJson(Map<String, dynamic> json) {
    status = json['status'];
    message = json['message'];
    data = json['data'] != null ? new Data.fromJson(json['data']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['status'] = this.status;
    data['message'] = this.message;
    if (this.data != null) {
      data['data'] = this.data!.toJson();
    }
    return data;
  }
}

class Data {
  String? id;
  String? name;
  String? firstName;
  String? lastName;
  String? email;
  String? phone;
  String? address;
  String? identificationNo;
  String? identificationType;
  String? bvn;

  Data(
      {this.id,
        this.name,
        this.firstName,
        this.lastName,
        this.email,
        this.phone,
        this.address,
        this.identificationNo,
        this.identificationType,
        this.bvn});

  Data.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    name = json['name'];
    firstName = json['first_name'];
    lastName = json['last_name'];
    email = json['email'];
    phone = json['phone'];
    address = json['address'];
    identificationNo = json['identification_no'];
    identificationType = json['identification_type'];
    bvn = json['bvn'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['id'] = this.id;
    data['name'] = this.name;
    data['first_name'] = this.firstName;
    data['last_name'] = this.lastName;
    data['email'] = this.email;
    data['phone'] = this.phone;
    data['address'] = this.address;
    data['identification_no'] = this.identificationNo;
    data['identification_type'] = this.identificationType;
    data['bvn'] = this.bvn;
    return data;
  }
}
