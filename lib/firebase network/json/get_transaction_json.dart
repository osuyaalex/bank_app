class GetMonthlyTransactions {
  String? status;
  String? message;
  String? timestamp;
  List<Data>? data;
  Meta? meta;

  GetMonthlyTransactions(
      {this.status, this.message, this.timestamp, this.data, this.meta});

  GetMonthlyTransactions.fromJson(Map<String, dynamic> json) {
    status = json['status'];
    message = json['message'];
    timestamp = json['timestamp'];
    if (json['data'] != null) {
      data = <Data>[];
      json['data'].forEach((v) {
        data!.add(new Data.fromJson(v));
      });
    }
    meta = json['meta'] != null ? new Meta.fromJson(json['meta']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['status'] = this.status;
    data['message'] = this.message;
    data['timestamp'] = this.timestamp;
    if (this.data != null) {
      data['data'] = this.data!.map((v) => v.toJson()).toList();
    }
    if (this.meta != null) {
      data['meta'] = this.meta!.toJson();
    }
    return data;
  }
}

class Data {
  String? id;
  String? narration;
  int? amount;
  String? type;
  int? balance;
  String? date;
  String? category;

  Data(
      {this.id,
        this.narration,
        this.amount,
        this.type,
        this.balance,
        this.date,
        this.category});

  Data.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    narration = json['narration'];
    amount = json['amount'];
    type = json['type'];
    balance = json['balance'];
    date = json['date'];
    category = json['category'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['id'] = this.id;
    data['narration'] = this.narration;
    data['amount'] = this.amount;
    data['type'] = this.type;
    data['balance'] = this.balance;
    data['date'] = this.date;
    data['category'] = this.category;
    return data;
  }
}

class Meta {
  int? total;
  int? page;
  Null? previous;
  String? next;

  Meta({this.total, this.page, this.previous, this.next});

  Meta.fromJson(Map<String, dynamic> json) {
    total = json['total'];
    page = json['page'];
    previous = json['previous'];
    next = json['next'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['total'] = this.total;
    data['page'] = this.page;
    data['previous'] = this.previous;
    data['next'] = this.next;
    return data;
  }
}
